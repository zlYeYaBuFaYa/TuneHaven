import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class PlaybackService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published var playMode: PlayMode = PlayMode(rawValue: UserDefaults.standard.integer(forKey: AppStorageKey.playMode)) ?? .sequential
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: AppStorageKey.playbackSpeed) == 0 ? 1.0 : UserDefaults.standard.float(forKey: AppStorageKey.playbackSpeed)
    let sleepTimer = SleepTimerService()

    var sleepTimerRemaining: TimeInterval? { sleepTimer.remaining }

    private let engine = AudioEngine.shared
    private let queueService: PlayQueueService
    private var libraryService: MusicLibraryService
    private let playlistRepo: PlaylistRepository
    private let songRepo: SongRepository
    private let imageCacheManager = ImageCacheManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentCover: UIImage?
    private var consecutivePlayNextFailures = 0
    private static let maxConsecutiveFailures = 5
    private var dislikes: [String: Int] {
        UserDefaults.standard.dictionary(forKey: AppStorageKey.songDislikes) as? [String: Int] ?? [:]
    }

    private static let lastPlayedSongIdKey = AppStorageKey.lastPlayedSongId

    init(playlistRepo: PlaylistRepository,
         songRepo: SongRepository) {
        self.queueService = PlayQueueService()
        self.libraryService = MusicLibraryService(songRepo: songRepo)
        self.playlistRepo = playlistRepo
        self.songRepo = songRepo
        setupBindings()
        sleepTimer.configure { [weak self] in
            self?.engine.pause()
            self?.isPlaying = false
        }
        Task { await restoreLastPlayedSong() }
    }

    private func restoreLastPlayedSong() async {
        guard let idString = UserDefaults.standard.string(forKey: Self.lastPlayedSongIdKey),
              let songId = UUID(uuidString: idString) else { return }
        guard let song = await songRepo.fetchSong(id: songId) else { return }
        currentSong = song
        queueService.replaceQueue(with: [song], startAt: 0)
    }

    func configure(libraryService: MusicLibraryService) {
        self.libraryService = libraryService
    }

    var queue: PlayQueueService { queueService }

    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }

    func play(song: Song, in context: PlayContext) async {
        log.info("播放: \(song.title) - \(song.artist)")
        if song.id == currentSong?.id {
            if case .playing = engine.state { return }
            if case .paused = engine.state {
                AudioSessionManager.shared.ensureActive()
                engine.play()
                isPlaying = true
                return
            }
        }

        if case .queue = context {
            await loadAndPlay(song: song)
            return
        }

        await buildQueue(for: song, in: context)
        await loadAndPlay(song: song)
    }

    func prepare(song: Song, in context: PlayContext) async {
        if song.id == currentSong?.id { return }

        if case .queue = context {
            await loadAndPlay(song: song, autoPlay: false)
            return
        }

        await buildQueue(for: song, in: context)
        await loadAndPlay(song: song, autoPlay: false)
    }

    func togglePlayPause() {
        if let song = currentSong, case .idle = engine.state {
            Task { await loadAndPlay(song: song) }
            return
        }
        engine.togglePlayPause()
    }

    func playNext() {
        queueService.markCurrentAsPlayed()
        guard let nextItem = queueService.nextSong(for: playMode, dislikes: dislikes) else {
            log.info("队列播放结束，无下一首")
            stop()
            return
        }
        log.debug("播放下一首: \(nextItem.song.title)")
        queueService.advanceToCurrent(nextItem)
        Task { await loadAndPlay(song: nextItem.song) }
    }

    func playPrevious() {
        let threshold: TimeInterval = 3
        if engine.currentTime > threshold {
            log.debug("播放进度 > 3s，回到歌曲开头")
            engine.seek(to: 0)
            return
        }
        guard let prevItem = queueService.previousSong() else { return }
        queueService.advanceToCurrent(prevItem)
        Task { await loadAndPlay(song: prevItem.song) }
    }

    func seek(to time: TimeInterval) {
        engine.seek(to: time)
        updateNowPlayingTime(currentTime: time)
    }

    func skip(by seconds: TimeInterval) {
        engine.skip(by: seconds)
    }

    func stop() {
        log.info("停止播放")
        engine.stop()
        isPlaying = false
        if let song = currentSong {
            NowPlayingManager.shared.update(
                song: song,
                currentTime: 0,
                duration: duration,
                speed: 0,
                cover: currentCover
            )
        }
    }

    func toggleCurrentSongFavorite() async {
        guard let song = currentSong else { return }
        do {
            try await libraryService.toggleFavorite(songId: song.id)
            if let updated = await songRepo.fetchSong(id: song.id) {
                currentSong = updated
            }
        } catch {
            log.error(error, context: "切换收藏状态失败")
        }
    }

    func cyclePlayMode() {
        let modes = PlayMode.allCases
        let current = modes.firstIndex(of: playMode) ?? 0
        setPlayMode(modes[(current + 1) % modes.count])
    }

    func setPlayMode(_ mode: PlayMode) {
        playMode = mode
        log.info("切换播放模式: \(mode.rawValue)")
        UserDefaults.standard.set(mode.rawValue, forKey: AppStorageKey.playMode)
    }

    // MARK: - Speed

    func setSpeed(_ speed: Float) {
        log.debug("设置播放速度: \(speed)x")
        playbackSpeed = speed
        engine.setSpeed(speed)

        let memMode = UserDefaults.standard.integer(forKey: AppStorageKey.speedMemoryMode)
        if memMode == 1, let song = currentSong {
            var perSongSpeeds = UserDefaults.standard.dictionary(forKey: AppStorageKey.perSongSpeeds) as? [String: Float] ?? [:]
            perSongSpeeds[song.id.uuidString] = speed
            UserDefaults.standard.set(perSongSpeeds, forKey: AppStorageKey.perSongSpeeds)
        } else {
            UserDefaults.standard.set(speed, forKey: AppStorageKey.playbackSpeed)
        }
    }

    private func applySpeedForSong(_ song: Song) {
        let memMode = UserDefaults.standard.integer(forKey: AppStorageKey.speedMemoryMode)
        if memMode == 1 {
            let perSongSpeeds = UserDefaults.standard.dictionary(forKey: AppStorageKey.perSongSpeeds) as? [String: Float] ?? [:]
            let speed = perSongSpeeds[song.id.uuidString] ?? 1.0
            playbackSpeed = speed
            engine.setSpeed(speed)
        } else {
            let speed = UserDefaults.standard.float(forKey: AppStorageKey.playbackSpeed)
            let effective: Float = speed == 0 ? 1.0 : speed
            if playbackSpeed != effective {
                playbackSpeed = effective
                engine.setSpeed(effective)
            }
        }
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int?) {
        sleepTimer.set(minutes: minutes)
    }

    func dislikeAndSkip() async {
        guard let song = currentSong else { return }
        var dislikes = self.dislikes
        let count = min((dislikes[song.id.uuidString] ?? 0) + 1, 5)
        dislikes[song.id.uuidString] = count
        UserDefaults.standard.set(dislikes, forKey: AppStorageKey.songDislikes)
        playNext()
    }

    func checkSleepTimerOnForeground() {
        sleepTimer.checkOnForeground()
    }

    // MARK: - Private

    private func buildQueue(for song: Song, in context: PlayContext) async {
        var songs: [Song]
        var startIndex = 0

        switch context {
        case .allSongs(let sortBy):
            songs = await songRepo.fetchAll(sortBy: sortBy, ascending: true)
            startIndex = songs.firstIndex(of: song) ?? 0
        case .album(let name, let artist):
            let detail = await libraryService.fetchAlbumDetail(album: name, artist: artist)
            songs = detail.songs
            startIndex = songs.firstIndex(of: song) ?? 0
        case .artist(let name):
            let detail = await libraryService.fetchArtistDetail(artist: name)
            songs = detail.allSongs
            startIndex = songs.firstIndex(of: song) ?? 0
        case .playlist(let id):
            if let detail = await playlistRepo.fetchPlaylistDetail(id: id) {
                songs = detail.songs
                startIndex = songs.firstIndex(of: song) ?? 0
            } else {
                songs = [song]
                startIndex = 0
            }
        case .queue:
            return
        }

        queueService.replaceQueue(with: songs, startAt: startIndex)
    }

    private func loadAndPlay(song: Song, autoPlay: Bool = true) async {
        let fileURL = SandboxPathManager.musicFileURL(relativePath: song.fileRelativePath)
        guard FileStorageService.shared.fileExists(relativePath: song.fileRelativePath) else {
            ErrorLogger.shared.log(.playbackFileNotFound(song.id), context: "PlaybackService.loadAndPlay")
            log.error("播放文件不存在: \(song.fileRelativePath)")
            consecutivePlayNextFailures += 1
            if consecutivePlayNextFailures >= Self.maxConsecutiveFailures {
                log.error("连续 \(consecutivePlayNextFailures) 首文件不存在，停止播放")
                consecutivePlayNextFailures = 0
                stop()
                return
            }
            playNext()
            return
        }
        consecutivePlayNextFailures = 0
        currentSong = song
        UserDefaults.standard.set(song.id.uuidString, forKey: Self.lastPlayedSongIdKey)

        AudioSessionManager.shared.ensureActive()

        await engine.load(url: fileURL)
        applySpeedForSong(song)

        if autoPlay {
            engine.play()
            isPlaying = true
            do {
                try await libraryService.recordPlay(songId: song.id)
            } catch {
                ErrorLogger.shared.log(.databaseError(error), context: "PlaybackService: recordPlay 失败 songId=\(song.id)")
                log.error(error, context: "recordPlay 记录播放失败")
            }
        }

        currentCover = loadCoverSync(for: song)
        NowPlayingManager.shared.update(
            song: song,
            currentTime: 0,
            duration: engine.duration,
            speed: autoPlay ? playbackSpeed : 0,
            cover: currentCover
        )
    }

    private func loadCoverSync(for song: Song) -> UIImage? {
        guard let path = song.coverImagePath else { return nil }
        return imageCacheManager.image(forKey: path)
    }

    private func updateNowPlayingTime(currentTime: TimeInterval) {
        guard let song = currentSong else { return }
        NowPlayingManager.shared.update(
            song: song,
            currentTime: currentTime,
            duration: engine.duration,
            speed: isPlaying ? playbackSpeed : 0,
            cover: currentCover
        )
    }

    private func setupBindings() {
        sleepTimer.$remaining.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        engine.$state.sink { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .playing = state {
                    self.isPlaying = true
                    self.updateNowPlayingTime(currentTime: self.engine.currentTime)
                } else if case .paused = state {
                    self.isPlaying = false
                    self.updateNowPlayingTime(currentTime: self.engine.currentTime)
                } else if case .idle = state {
                    self.isPlaying = false
                }
            }
        }.store(in: &cancellables)

        engine.playbackEndedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.playNext() }
            }
            .store(in: &cancellables)

        engine.timeUpdateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration in
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying, self.currentSong != nil else { return }
                    NowPlayingManager.shared.updateElapsedTime(currentTime: currentTime, duration: duration, speed: self.playbackSpeed)
                }
            }
            .store(in: &cancellables)

        NowPlayingManager.shared.setupRemoteCommands(
            onPlay: { [weak self] in
                Task { @MainActor in
                    AudioSessionManager.shared.ensureActive()
                    self?.engine.play()
                }
            },
            onPause: { [weak self] in
                Task { @MainActor in self?.engine.pause() }
            },
            onTogglePlayPause: { [weak self] in
                Task { @MainActor in self?.togglePlayPause() }
            },
            onNext: { [weak self] in
                Task { @MainActor in self?.playNext() }
            },
            onPrevious: { [weak self] in
                Task { @MainActor in self?.playPrevious() }
            },
            onSeek: { [weak self] time in
                Task { @MainActor in self?.engine.seek(to: time) }
            }
        )
    }

}

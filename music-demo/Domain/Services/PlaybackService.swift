import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class PlaybackService: ObservableObject {
    static let shared = PlaybackService()

    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published var playMode: PlayMode = PlayMode(rawValue: UserDefaults.standard.integer(forKey: "play_mode")) ?? .sequential
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: "playback_speed") == 0 ? 1.0 : UserDefaults.standard.float(forKey: "playback_speed")
    @Published var sleepTimerRemaining: TimeInterval? = nil

    private let engine = AudioEngine.shared
    private let queueService: PlayQueueService
    private let libraryService: MusicLibraryService
    private let songRepo = CoreDataSongRepository()
    private let imageCacheManager = ImageCacheManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var sleepTimerEndDate: Date?
    private var sleepTimerTimer: Timer?
    private var currentCover: UIImage?
    private var dislikes: [String: Int] {
        UserDefaults.standard.dictionary(forKey: "song_dislikes") as? [String: Int] ?? [:]
    }

    private init() {
        self.queueService = PlayQueueService()
        self.libraryService = MusicLibraryService()
        setupBindings()
    }

    var queue: PlayQueueService { queueService }

    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }

    func play(song: Song, in context: PlayContext) async {
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
            songs = [song]
            startIndex = 0
            _ = id
        case .queue:
            await loadAndPlay(song: song)
            return
        }

        queueService.replaceQueue(with: songs, startAt: startIndex)
        await loadAndPlay(song: song)
    }

    func togglePlayPause() {
        engine.togglePlayPause()
    }

    func playNext() {
        queueService.markCurrentAsPlayed()
        guard let nextItem = queueService.nextSong(for: playMode, dislikes: dislikes) else {
            stop()
            return
        }
        queueService.advanceToCurrent(nextItem)
        Task { await loadAndPlay(song: nextItem.song) }
    }

    func playPrevious() {
        let threshold: TimeInterval = 3
        if engine.currentTime > threshold {
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
        engine.stop()
        isPlaying = false
        currentSong = nil
        currentCover = nil
        NowPlayingManager.shared.clear()
    }

    func toggleCurrentSongFavorite() {
        guard var song = currentSong else { return }
        song.isFavorite.toggle()
        currentSong = song
    }

    func cyclePlayMode() {
        let modes = PlayMode.allCases
        let current = modes.firstIndex(of: playMode) ?? 0
        playMode = modes[(current + 1) % modes.count]
        UserDefaults.standard.set(playMode.rawValue, forKey: "play_mode")
    }

    // MARK: - Speed

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        engine.setSpeed(speed)

        let memMode = UserDefaults.standard.integer(forKey: "speed_memory_mode")
        if memMode == 1, let song = currentSong {
            var perSongSpeeds = UserDefaults.standard.dictionary(forKey: "per_song_speeds") as? [String: Float] ?? [:]
            perSongSpeeds[song.id.uuidString] = speed
            UserDefaults.standard.set(perSongSpeeds, forKey: "per_song_speeds")
        } else {
            UserDefaults.standard.set(speed, forKey: "playback_speed")
        }
    }

    private func applySpeedForSong(_ song: Song) {
        let memMode = UserDefaults.standard.integer(forKey: "speed_memory_mode")
        if memMode == 1 {
            let perSongSpeeds = UserDefaults.standard.dictionary(forKey: "per_song_speeds") as? [String: Float] ?? [:]
            let speed = perSongSpeeds[song.id.uuidString] ?? 1.0
            playbackSpeed = speed
            engine.setSpeed(speed)
        } else {
            let speed = UserDefaults.standard.float(forKey: "playback_speed")
            let effective: Float = speed == 0 ? 1.0 : speed
            if playbackSpeed != effective {
                playbackSpeed = effective
                engine.setSpeed(effective)
            }
        }
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int?) {
        sleepTimerTimer?.invalidate()
        sleepTimerTimer = nil
        sleepTimerEndDate = nil
        sleepTimerRemaining = nil

        guard let minutes, minutes > 0 else { return }
        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEndDate = endDate

        sleepTimerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickSleepTimer() }
        }
    }

    func dislikeAndSkip() async {
        guard let song = currentSong else { return }
        var dislikes = self.dislikes
        let count = min((dislikes[song.id.uuidString] ?? 0) + 1, 5)
        dislikes[song.id.uuidString] = count
        UserDefaults.standard.set(dislikes, forKey: "song_dislikes")
        playNext()
    }

    func checkSleepTimerOnForeground() {
        guard let endDate = sleepTimerEndDate, Date() >= endDate else { return }
        executeSleepTimerStop()
    }

    // MARK: - Private

    private func loadAndPlay(song: Song) async {
        currentSong = song
        let fileURL = SandboxPathManager.musicFileURL(relativePath: song.fileRelativePath)
        guard FileStorageService.shared.fileExists(relativePath: song.fileRelativePath) else {
            ErrorLogger.shared.log(.playbackFileNotFound(song.id), context: "PlaybackService.loadAndPlay")
            return
        }

        AudioSessionManager.shared.ensureActive()

        await engine.load(url: fileURL)
        applySpeedForSong(song)
        engine.setSpeed(playbackSpeed)
        engine.play()
        isPlaying = true
        try? await libraryService.recordPlay(songId: song.id)

        currentCover = loadCoverSync(for: song)
        NowPlayingManager.shared.update(
            song: song,
            currentTime: 0,
            duration: engine.duration,
            speed: playbackSpeed,
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

        engine.onPlaybackEnded = { [weak self] in
            Task { @MainActor [weak self] in self?.playNext() }
        }

        // Periodically update NowPlayingInfo so iOS knows we're still actively playing
        engine.onTimeUpdate = { [weak self] currentTime, duration in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying, let song = self.currentSong else { return }
                NowPlayingManager.shared.updateElapsedTime(currentTime: currentTime, duration: duration, speed: self.playbackSpeed)
            }
        }

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

    private func tickSleepTimer() {
        guard let endDate = sleepTimerEndDate else { return }
        let remaining = endDate.timeIntervalSince(Date())
        if remaining <= 0 {
            executeSleepTimerStop()
        } else {
            sleepTimerRemaining = remaining
        }
    }

    private func executeSleepTimerStop() {
        sleepTimerTimer?.invalidate()
        sleepTimerTimer = nil
        sleepTimerEndDate = nil
        sleepTimerRemaining = nil
        engine.pause()
        isPlaying = false
    }
}

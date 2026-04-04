import Combine
import Foundation

@MainActor
final class PlaybackService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var playMode: PlayMode
    @Published private(set) var playbackSpeed: Float
    let sleepTimer: SleepTimerService

    var sleepTimerRemaining: TimeInterval? { sleepTimer.remaining }
    var sleepTimerOriginalMinutes: Int? { sleepTimer.originalMinutes }

    private let engine: any AudioEngineProtocol
    private let queueService: PlayQueueService
    private let libraryService: MusicLibraryService
    private let playlistRepo: PlaylistRepository
    private let songRepo: SongRepository
    private let audioSession: AudioSessionManaging
    private let nowPlaying: NowPlayingManaging
    private let fileStorage: FileStorageProviding
    private let preferences: UserPreferencesProviding
    private let subscriptionService: SubscriptionService
    private var cancellables = Set<AnyCancellable>()
    private var currentCoverPath: String?
    private var consecutivePlayNextFailures = 0
    private var loadTask: Task<Void, Never>?
    private static let maxConsecutiveFailures = 5
    private static let maxLosslessSkips = 50

    @Published private(set) var losslessBlockedSong: Song?

    func clearLosslessBlock() {
        losslessBlockedSong = nil
    }

    init(playlistRepo: PlaylistRepository,
         songRepo: SongRepository,
         queueService: PlayQueueService,
         libraryService: MusicLibraryService,
         engine: any AudioEngineProtocol,
         audioSession: AudioSessionManaging,
         nowPlaying: NowPlayingManaging,
         fileStorage: FileStorageProviding,
         preferences: UserPreferencesProviding,
         sleepTimer: SleepTimerService,
         subscriptionService: SubscriptionService) {
        self.queueService = queueService
        self.libraryService = libraryService
        self.playlistRepo = playlistRepo
        self.songRepo = songRepo
        self.engine = engine
        self.audioSession = audioSession
        self.nowPlaying = nowPlaying
        self.fileStorage = fileStorage
        self.preferences = preferences
        self.sleepTimer = sleepTimer
        self.subscriptionService = subscriptionService
        self.playMode = preferences.playMode
        self.playbackSpeed = preferences.playbackSpeed
        setupBindings()
        sleepTimer.configure { [weak self] in
            self?.engine.pause()
            self?.isPlaying = false
        }
        Task { await restoreLastPlayedSong() }
    }

    private func restoreLastPlayedSong() async {
        guard let idString = preferences.lastPlayedSongId,
              let songId = UUID(uuidString: idString) else { return }
        guard let song = await songRepo.fetchSong(id: songId) else { return }
        currentSong = song
        queueService.replaceQueue(with: [song], startAt: 0)
    }

    var queue: PlayQueueService { queueService }

    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }

    func play(song: Song, in context: PlayContext) async {
        if song.isLossless && !subscriptionService.canAccess(.losslessPlayback) {
            log.info("Free 用户尝试播放无损: \(song.title)")
            losslessBlockedSong = song
            return
        }
        log.info("播放: \(song.title) - \(song.artist)")
        if song.id == currentSong?.id {
            if case .playing = engine.state { return }
            if case .paused = engine.state {
                audioSession.ensureActive()
                engine.play()
                isPlaying = true
                return
            }
            // .idle / .error / .loading → fall through to reload
        }

        loadTask?.cancel()

        if case .queue = context {
            await loadAndPlay(song: song)
            return
        }

        await buildQueue(for: song, in: context)
        await loadAndPlay(song: song)
    }

    func prepare(song: Song, in context: PlayContext) async {
        if song.isLossless && !subscriptionService.canAccess(.losslessPlayback) {
            log.info("Free 用户预加载无损被拦截: \(song.title)")
            losslessBlockedSong = song
            return
        }
        if song.id == currentSong?.id { return }

        loadTask?.cancel()

        if case .queue = context {
            await loadAndPlay(song: song, autoPlay: false)
            return
        }

        await buildQueue(for: song, in: context)
        await loadAndPlay(song: song, autoPlay: false)
    }

    func togglePlayPause() {
        if let song = currentSong, song.isLossless,
           !subscriptionService.canAccess(.losslessPlayback) {
            losslessBlockedSong = song
            return
        }
        if let song = currentSong, case .idle = engine.state {
            startLoadAndPlay(song: song)
            return
        }
        engine.togglePlayPause()
    }

    func playNext() {
        queueService.markCurrentAsPlayed()

        var skipCount = 0
        while let nextItem = queueService.nextSong(for: playMode, dislikes: preferences.songDislikes) {
            if nextItem.song.isLossless && !subscriptionService.canAccess(.losslessPlayback) {
                skipCount += 1
                if skipCount >= Self.maxLosslessSkips {
                    log.info("连续跳过 \(skipCount) 首无损歌曲，停止播放")
                    stop()
                    return
                }
                log.debug("跳过无损歌曲: \(nextItem.song.title)")
                queueService.advanceToCurrent(nextItem)
                queueService.markCurrentAsPlayed()
                continue
            }
            log.debug("播放下一首: \(nextItem.song.title)")
            queueService.advanceToCurrent(nextItem)
            startLoadAndPlay(song: nextItem.song)
            return
        }
        log.info("队列播放结束，无下一首")
        stop()
    }

    func playPrevious() {
        let threshold: TimeInterval = 3
        if engine.currentTime > threshold {
            log.debug("播放进度 > 3s，回到歌曲开头")
            engine.seek(to: 0)
            return
        }
        guard let prevItem = queueService.previousSong() else { return }
        if prevItem.song.isLossless && !subscriptionService.canAccess(.losslessPlayback) {
            losslessBlockedSong = prevItem.song
            return
        }
        queueService.advanceToCurrent(prevItem)
        startLoadAndPlay(song: prevItem.song)
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
            Task {
                await nowPlaying.update(
                    song: song,
                    currentTime: 0,
                    duration: duration,
                    speed: 0,
                    coverPath: currentCoverPath
                )
            }
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
        preferences.playMode = mode
    }

    // MARK: - Speed

    func setSpeed(_ speed: Float) {
        log.debug("设置播放速度: \(speed)x")
        playbackSpeed = speed
        engine.setSpeed(speed)

        if preferences.speedMemoryMode == .perSong, let song = currentSong {
            var perSongSpeeds = preferences.perSongSpeeds
            perSongSpeeds[song.id.uuidString] = speed
            preferences.perSongSpeeds = perSongSpeeds
        } else {
            preferences.playbackSpeed = speed
        }
    }

    private func applySpeedForSong(_ song: Song) {
        if preferences.speedMemoryMode == .perSong {
            let speed = preferences.perSongSpeeds[song.id.uuidString] ?? 1.0
            playbackSpeed = speed
            engine.setSpeed(speed)
        } else {
            let effective = preferences.playbackSpeed
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
        var dislikes = preferences.songDislikes
        let count = min((dislikes[song.id.uuidString] ?? 0) + 1, 5)
        dislikes[song.id.uuidString] = count
        preferences.songDislikes = dislikes
        playNext()
    }

    func checkSleepTimerOnForeground() {
        sleepTimer.checkOnForeground()
    }

    // MARK: - Private

    private func startLoadAndPlay(song: Song, autoPlay: Bool = true) {
        loadTask?.cancel()
        loadTask = Task {
            await loadAndPlay(song: song, autoPlay: autoPlay)
        }
    }

    private func buildQueue(for song: Song, in context: PlayContext) async {
        var songs: [Song]
        var startIndex = 0

        switch context {
        case .allSongs(let sortBy):
            do {
                songs = try await songRepo.fetchAll(sortBy: sortBy, ascending: true)
            } catch {
                log.error(error, context: "构建播放队列时获取歌曲失败")
                songs = []
            }
            startIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        case .album(let name, let artist):
            let detail = await libraryService.fetchAlbumDetail(album: name, artist: artist)
            songs = detail.songs
            startIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        case .artist(let name):
            let detail = await libraryService.fetchArtistDetail(artist: name)
            songs = detail.allSongs
            startIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        case .playlist(let id):
            if let detail = await playlistRepo.fetchPlaylistDetail(id: id) {
                songs = detail.songs
                startIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
            } else {
                songs = [song]
                startIndex = 0
            }
        case .recentlyPlayed(let days):
            let result = await libraryService.fetchRecentlyPlayed(days: days, page: 0, pageSize: 1000)
            songs = result.items
            startIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        case .queue:
            return
        }

        queueService.replaceQueue(with: songs, startAt: startIndex)
    }

    private func loadAndPlay(song: Song, autoPlay: Bool = true) async {
        let fileURL = fileStorage.musicFileURL(relativePath: song.fileRelativePath)
        guard fileStorage.fileExists(relativePath: song.fileRelativePath) else {
            log.error(AppError.playbackFileNotFound(song.id), context: "PlaybackService.loadAndPlay")
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
        preferences.lastPlayedSongId = song.id.uuidString

        audioSession.ensureActive()

        await engine.load(url: fileURL)

        guard !Task.isCancelled, currentSong?.id == song.id else { return }

        applySpeedForSong(song)

        if autoPlay {
            engine.play()
            isPlaying = true
            do {
                try await libraryService.recordPlay(songId: song.id)
            } catch {
                log.error(error, context: "recordPlay 记录播放失败")
            }
        }

        currentCoverPath = song.coverImagePath
        await nowPlaying.update(
            song: song,
            currentTime: 0,
            duration: engine.duration,
            speed: autoPlay ? playbackSpeed : 0,
            coverPath: currentCoverPath
        )
    }

    private func updateNowPlayingTime(currentTime: TimeInterval) {
        guard let song = currentSong else { return }
        Task {
            await nowPlaying.update(
                song: song,
                currentTime: currentTime,
                duration: engine.duration,
                speed: isPlaying ? playbackSpeed : 0,
                coverPath: currentCoverPath
            )
        }
    }

    private func setupBindings() {
        sleepTimer.$remaining.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        // iOS 16.4: sink 闭包为 @Sendable，需 Task { @MainActor } 跨隔离域访问 self；
        // iOS 17+ 可改用 MainActor.assumeIsolated
        engine.statePublisher.sink { [weak self] state in
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

        engine.playbackEndedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.playNext() }
            }
            .store(in: &cancellables)

        engine.timeUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration in
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying, self.currentSong != nil else { return }
                    self.nowPlaying.updateElapsedTime(currentTime: currentTime, duration: duration, speed: self.playbackSpeed)
                }
            }
            .store(in: &cancellables)

        nowPlaying.setupRemoteCommands(
            onPlay: { [weak self] in
                Task { @MainActor in
                    self?.audioSession.ensureActive()
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

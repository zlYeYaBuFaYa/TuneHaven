import Combine
import Foundation

@MainActor
final class PlaybackService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published var playMode: PlayMode
    @Published var playbackSpeed: Float
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

    @Published private(set) var losslessBlockedSong: Song?
    /// 启动时因档位（可能只是本地推断的临时 Free）没恢复的上次无损歌曲，档位变为 Premium 后补回
    private var pendingLosslessRestore: Song?

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
    }

    /// 须在订阅状态解析之后调用。Free 不把无损歌曲恢复成可播放的 `currentSong`，
    /// 也不预置付费墙信号，避免冷启动硬挡进库。
    func restoreLastPlayedSong() async {
        guard let idString = preferences.lastPlayedSongId,
              let songId = UUID(uuidString: idString) else { return }
        guard let song = await songRepo.fetchSong(id: songId) else { return }
        guard !deniesLossless(song) else {
            log.info("Free 用户不恢复无损为当前歌曲: \(song.title)")
            currentSong = nil
            pendingLosslessRestore = song
            return
        }
        currentSong = song
        queueService.replaceQueue(with: [song], startAt: 0)
    }

    /// 无损播放统一门禁。无权限时写入 `losslessBlockedSong` 并返回 false。
    @discardableResult
    func ensureCanPlay(_ song: Song) -> Bool {
        guard deniesLossless(song) else { return true }
        log.info("Free 用户无法播放无损: \(song.title)")
        losslessBlockedSong = song
        return false
    }

    private func deniesLossless(_ song: Song) -> Bool {
        song.isLossless && !subscriptionService.canAccess(.losslessPlayback)
    }

    var queue: PlayQueueService { queueService }

    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }

    func play(song: Song, in context: PlayContext) async {
        guard ensureCanPlay(song) else { return }
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
        guard ensureCanPlay(song) else { return }
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
        // 没有当前歌曲时引擎没有可播的内容，不能把状态置为播放中
        guard let song = currentSong else { return }
        if !ensureCanPlay(song) { return }
        if case .idle = engine.state {
            startLoadAndPlay(song: song)
            return
        }
        engine.togglePlayPause()
    }

    func playNext() {
        if isPlayingOutsideQueue {
            // 队列外播放结束：从原后继项继续，没有后继就停止
            let successorId = outOfQueueSuccessorId
            exitOutOfQueue()
            guard let successorId, let next = queueService.queue.first(where: { $0.id == successorId }) else {
                log.info("队列外播放结束，无后继")
                stop()
                return
            }
            queueService.advanceToCurrent(next)
            guard ensureCanPlay(next.song) else {
                parkOnBlockedSong(next.song)
                return
            }
            startLoadAndPlay(song: next.song)
            return
        }
        queueService.markCurrentAsPlayed()
        guard let nextItem = queueService.nextSong(for: playMode, dislikes: preferences.songDislikes) else {
            log.info("队列播放结束，无下一首")
            stop()
            return
        }
        queueService.advanceToCurrent(nextItem)
        guard ensureCanPlay(nextItem.song) else {
            parkOnBlockedSong(nextItem.song)
            return
        }
        log.debug("播放下一首: \(nextItem.song.title)")
        startLoadAndPlay(song: nextItem.song)
    }

    func playPrevious() {
        let threshold: TimeInterval = 3
        if engine.currentTime > threshold {
            if let song = currentSong, !ensureCanPlay(song) {
                parkOnBlockedSong(song)
                return
            }
            log.debug("播放进度 > 3s，回到歌曲开头")
            engine.seek(to: 0)
            return
        }
        guard let prevItem = queueService.previousSong() else { return }
        queueService.advanceToCurrent(prevItem)
        guard ensureCanPlay(prevItem.song) else {
            parkOnBlockedSong(prevItem.song)
            return
        }
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

    // MARK: - Queue Editing

    /// 当前歌曲已被移出队列但仍在播放（交互设计 §7.5「队列外播放」）。播完后从原后继项继续
    @Published private(set) var isPlayingOutsideQueue = false
    /// 队列外播放结束后接着播放的条目（QueueItem id）；为 nil 表示播完即停止
    private var outOfQueueSuccessorId: UUID?

    /// 队列外播放结束后接着播放的歌曲，供队列页说明「播完后继续：…」；nil 表示播完即停止
    var outOfQueueSuccessor: Song? {
        guard isPlayingOutsideQueue, let id = outOfQueueSuccessorId else { return nil }
        return queueService.queue.first { $0.id == id }?.song
    }

    /// 用户编辑队列时移除条目。移除当前项不切断音频：进入队列外播放，记住原后继项。
    func removeFromQueue(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        let items = queueService.queue
        if let idx = queueService.currentIndex, offsets.contains(idx) {
            let successor = Self.firstItem(in: items, after: idx, excluding: offsets)
            queueService.removeFromQueue(at: offsets)
            queueService.detachCurrent()
            enterOutOfQueue(successorId: successor)
            return
        }
        if isPlayingOutsideQueue, let successorId = outOfQueueSuccessorId,
           let successorIdx = items.firstIndex(where: { $0.id == successorId }),
           offsets.contains(successorIdx) {
            outOfQueueSuccessorId = Self.firstItem(in: items, after: successorIdx, excluding: offsets)
        }
        queueService.removeFromQueue(at: offsets)
    }

    /// 清空队列：当前音频继续到结束后停止，不重建列表
    func clearQueue() {
        queueService.clearQueue()
        if currentSong != nil {
            enterOutOfQueue(successorId: nil)
        }
    }

    /// 音乐库删除歌曲后同步队列。文件已被移走无法继续播放，所以删到当前歌曲时立即切到后继项
    /// （原来在播放就继续播放，否则保持暂停），没有后继则停止并清空当前歌曲。
    func removeSongsFromQueue(ids: Set<UUID>) {
        let items = queueService.queue
        let offsets = IndexSet(items.indices.filter { ids.contains(items[$0].song.id) })
        let deletesCurrent = currentSong.map { ids.contains($0.id) } ?? false
        guard deletesCurrent else {
            removeFromQueue(at: offsets)
            return
        }

        // 后继：队列中的当前项之后，或队列外播放记住的后继，跳过同样被删的条目
        var successorId: UUID?
        if let idx = queueService.currentIndex, items.indices.contains(idx), items[idx].song.id == currentSong?.id {
            successorId = Self.firstItem(in: items, after: idx, excluding: offsets)
        } else if isPlayingOutsideQueue, let pending = outOfQueueSuccessorId,
                  let pendingIdx = items.firstIndex(where: { $0.id == pending }) {
            successorId = offsets.contains(pendingIdx)
                ? Self.firstItem(in: items, after: pendingIdx, excluding: offsets)
                : pending
        }

        let wasPlaying = isPlaying
        queueService.removeFromQueue(at: offsets)
        exitOutOfQueue()
        guard let successorId, let next = queueService.queue.first(where: { $0.id == successorId }) else {
            stopAndClearCurrent()
            return
        }
        queueService.advanceToCurrent(next)
        guard ensureCanPlay(next.song) else {
            parkOnBlockedSong(next.song)
            return
        }
        startLoadAndPlay(song: next.song, autoPlay: wasPlaying)
    }

    private static func firstItem(in items: [QueueItem], after index: Int, excluding offsets: IndexSet) -> UUID? {
        items.indices.first { $0 > index && !offsets.contains($0) }.map { items[$0].id }
    }

    private func enterOutOfQueue(successorId: UUID?) {
        isPlayingOutsideQueue = true
        outOfQueueSuccessorId = successorId
    }

    private func exitOutOfQueue() {
        isPlayingOutsideQueue = false
        outOfQueueSuccessorId = nil
    }

    private func stopAndClearCurrent() {
        loadTask?.cancel()
        engine.stop()
        isPlaying = false
        currentSong = nil
        currentCoverPath = nil
        nowPlaying.clear()
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
        guard ensureCanPlay(song) else { return }
        // 开始加载新歌曲即退出队列外播放（点歌、上一首、从其他列表播放）
        exitOutOfQueue()
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

        // 不在这里激活音频会话：只预备不播放时不应打断其他 App，开播时 engine.play() 会激活
        await engine.load(url: fileURL)

        guard !Task.isCancelled, currentSong?.id == song.id else { return }

        applySpeedForSong(song)

        // 加载期间可能已经降为 Free。handleTierChange 只暂停「正在播放」的无损，
        // 挡不住随后这次 engine.play()，所以开播前再验一次。
        // 拦截后立刻返回、不再 await，好让调用方的 openPlayer() 赶在 SwiftUI 刷新前落地，
        // 全屏播放器才能接住这次付费墙信号。
        let canAutoPlay = autoPlay && ensureCanPlay(song)
        if autoPlay && !canAutoPlay {
            engine.pause()
            isPlaying = false
            currentCoverPath = song.coverImagePath
            let cover = currentCoverPath
            let loadedDuration = engine.duration
            Task { @MainActor in
                await nowPlaying.update(
                    song: song,
                    currentTime: 0,
                    duration: loadedDuration,
                    speed: 0,
                    coverPath: cover
                )
            }
            return
        }

        if canAutoPlay {
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
            speed: canAutoPlay ? playbackSpeed : 0,
            coverPath: currentCoverPath
        )
    }

    /// 编辑歌曲信息后，播放器、队列和锁屏不再显示旧标题。
    private func applyEditedSong(_ song: Song) {
        queueService.updateSong(song)
        guard currentSong?.id == song.id else { return }
        currentSong = song
        updateNowPlayingTime(currentTime: engine.currentTime)
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

        libraryService.songsDeleted
            .sink { [weak self] ids in
                Task { @MainActor [weak self] in
                    self?.removeSongsFromQueue(ids: ids)
                }
            }
            .store(in: &cancellables)

        libraryService.songUpdated
            .sink { [weak self] song in
                Task { @MainActor [weak self] in
                    self?.applyEditedSong(song)
                }
            }
            .store(in: &cancellables)

        subscriptionService.$tier
            .sink { [weak self] tier in
                Task { @MainActor [weak self] in
                    self?.handleTierChange(tier)
                }
            }
            .store(in: &cancellables)

        nowPlaying.setupRemoteCommands(
            onPlay: { [weak self] in
                Task { @MainActor in
                    self?.handleRemotePlay()
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

    /// 锁屏/控制中心的 Play 不得裸调 `engine.play()`。无当前歌曲时不做任何事。
    private func handleRemotePlay() {
        guard let song = currentSong, ensureCanPlay(song) else { return }
        if case .playing = engine.state { return }
        if case .paused = engine.state {
            audioSession.ensureActive()
            engine.play()
            isPlaying = true
            return
        }
        startLoadAndPlay(song: song)
    }

    /// 停在被拦截的目标歌曲上并保持软付费墙信号，不静默跳过、也不继续出声。
    private func parkOnBlockedSong(_ song: Song) {
        engine.stop()
        isPlaying = false
        currentSong = song
        currentCoverPath = song.coverImagePath
        Task {
            await nowPlaying.update(
                song: song,
                currentTime: 0,
                duration: song.duration,
                speed: 0,
                coverPath: song.coverImagePath
            )
        }
    }

    /// 到期降为 Free 时，只暂停正在播放的无损，不打断有损会话。
    private func handleTierChange(_ tier: SubscriptionTier) {
        if tier == .premium, let pending = pendingLosslessRestore {
            pendingLosslessRestore = nil
            // 用户这期间已经选了别的歌，就不覆盖
            if currentSong == nil {
                log.info("档位确认为 Premium，补回上次无损歌曲: \(pending.title)")
                currentSong = pending
                queueService.replaceQueue(with: [pending], startAt: 0)
            }
        }
        guard tier == .free, let song = currentSong, song.isLossless else { return }
        let enginePlaying: Bool
        if case .playing = engine.state {
            enginePlaying = true
        } else {
            enginePlaying = false
        }
        guard isPlaying || enginePlaying else { return }
        log.info("订阅降为 Free，暂停正在播放的无损: \(song.title)")
        engine.pause()
        isPlaying = false
        losslessBlockedSong = song
    }

}

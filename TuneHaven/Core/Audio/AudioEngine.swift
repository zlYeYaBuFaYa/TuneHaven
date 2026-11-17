import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioEngine: ObservableObject, AudioEngineProtocol {
    static let shared = AudioEngine()
    private let log = AppLogger.shared

    @Published var state: PlaybackState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isBuffering: Bool = false
    @Published var playbackSpeed: Float = 1.0

    private var player: AVPlayer
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    /// 每次 load 递增。load 中途有新的 load 发起时，旧的在 await 之后放弃，避免快速切歌时把旧 item 换回来
    private var loadGeneration = 0
    /// 中断开始时是否在播放。中断结束只在原来播放时才恢复
    private var wasPlayingBeforeInterruption = false

    #if DEBUG
    /// 测试用：在读取资源前插入延迟，确定性地制造「先发起的加载后完成」
    var beforeAssetLoadForTesting: ((URL) async -> Void)?
    #endif

    /// 当前 item 的文件地址
    var currentItemURL: URL? {
        (player.currentItem?.asset as? AVURLAsset)?.url
    }

    private var interruptionObserver: Any?
    private var routeChangeObserver: Any?
    private var playbackEndedObserver: Any?

    private static let playableExtensions: Set<String> = [
        "mp3", "m4a", "aac", "alac", "wav", "flac", "aiff", "aif", "caf"
    ]

    private init() {
        self.player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        setupNotifications()
    }

    func cleanup() {
        stop()
        if let o = interruptionObserver { NotificationCenter.default.removeObserver(o); interruptionObserver = nil }
        if let o = routeChangeObserver { NotificationCenter.default.removeObserver(o); routeChangeObserver = nil }
    }

    func load(url: URL) async {
        loadGeneration += 1
        let generation = loadGeneration
        stop()
        state = .loading
        log.info("加载音频: \(url.lastPathComponent)")

        guard FileManager.default.fileExists(atPath: url.path) else {
            state = .error(AppError.playbackLoadFailed("文件不存在: \(url.lastPathComponent)"))
            log.error("音频文件不存在: \(url.path)")
            return
        }

        let ext = url.pathExtension.lowercased()
        guard Self.playableExtensions.contains(ext) else {
            state = .error(AppError.playbackUnsupportedFormat(ext))
            log.error("不支持的音频格式: \(ext)")
            return
        }

        // 只加载不激活音频会话，激活留给 play()，否则只是预备一首歌也会打断其他 App 的音频
        let asset = AVURLAsset(url: url)
        #if DEBUG
        await beforeAssetLoadForTesting?(url)
        #endif

        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard generation == loadGeneration else { return }
            guard isPlayable else {
                state = .error(AppError.playbackLoadFailed(url.lastPathComponent))
                log.error("音频资源不可播放: \(url.lastPathComponent)")
                return
            }
        } catch {
            guard generation == loadGeneration else { return }
            state = .error(AppError.playbackLoadFailed(error.localizedDescription))
            log.error(error, context: "音频资源加载失败: \(url.lastPathComponent)")
            return
        }

        let item = AVPlayerItem(asset: asset)
        playerItem = item

        statusObservation?.invalidate()
        itemObservation?.invalidate()

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay:
                    self?.isBuffering = false
                case .failed:
                    if let err = error {
                        self?.state = .error(AppError.playbackUnsupportedFormat("加载失败：\(err.localizedDescription)"))
                    }
                default: break
                }
            }
        }

        itemObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            let empty = item.isPlaybackBufferEmpty
            Task { @MainActor [weak self] in
                self?.isBuffering = empty
            }
        }

        player.replaceCurrentItem(with: item)
        addTimeObserver()

        do {
            let dur = try await asset.load(.duration)
            guard generation == loadGeneration else { return }
            duration = dur.seconds.isNaN ? 0 : dur.seconds
        } catch {
            log.info("duration 加载失败，将从 playerItem 补充获取: \(error.localizedDescription)")
        }
    }

    func play() {
        guard AudioSessionManager.shared.ensureActive() else {
            state = .error(AppError.playbackSessionFailed)
            log.error("音频会话激活失败，无法播放")
            return
        }
        player.rate = playbackSpeed
        state = .playing
        log.debug("开始播放")
    }

    func pause() {
        player.pause()
        state = .paused
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 1000)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(by seconds: TimeInterval) {
        let newTime = max(0, min(currentTime + seconds, duration))
        seek(to: newTime)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeTimeObserver()
        statusObservation?.invalidate()
        statusObservation = nil
        itemObservation?.invalidate()
        itemObservation = nil
        playerItem = nil
        state = .idle
        log.debug("停止播放引擎")
        currentTime = 0
        duration = 0
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }

    private let _playbackEndedSubject = PassthroughSubject<Void, Never>()
    private let _timeUpdateSubject = PassthroughSubject<(currentTime: TimeInterval, duration: TimeInterval), Never>()
    var playbackEndedSubject: AnyPublisher<Void, Never> { _playbackEndedSubject.eraseToAnyPublisher() }
    var timeUpdateSubject: AnyPublisher<(currentTime: TimeInterval, duration: TimeInterval), Never> { _timeUpdateSubject.eraseToAnyPublisher() }

    // MARK: - AudioEngineProtocol
    var statePublisher: AnyPublisher<PlaybackState, Never> { $state.eraseToAnyPublisher() }
    var playbackEndedPublisher: AnyPublisher<Void, Never> { playbackEndedSubject }
    var timeUpdatePublisher: AnyPublisher<(currentTime: TimeInterval, duration: TimeInterval), Never> { timeUpdateSubject }

    private func addTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = seconds
                self._timeUpdateSubject.send((currentTime: seconds, duration: self.duration))
            }
        }
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = .paused
                self.log.info("当前曲目播放结束")
                self.currentTime = self.duration
                self._playbackEndedSubject.send()
            }
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        if let o = playbackEndedObserver { NotificationCenter.default.removeObserver(o); playbackEndedObserver = nil }
    }

    private func setupNotifications() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            state = .paused
            log.info("音频中断开始")
        case .ended:
            let wasPlaying = wasPlayingBeforeInterruption
            wasPlayingBeforeInterruption = false
            if let optValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optValue)
                // 中断前用户已暂停的，不因 shouldResume 自行开始播放
                if options.contains(.shouldResume) && wasPlaying {
                    guard AudioSessionManager.shared.ensureActive() else {
                        log.error("音频中断恢复失败：无法激活音频会话")
                        return
                    }
                    player.rate = playbackSpeed
                    state = .playing
                    log.info("音频中断结束，恢复播放")
                }
            }
        @unknown default: break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            player.pause()
            state = .paused
            log.info("音频路由变更（设备断开），暂停播放")
        }
    }
}

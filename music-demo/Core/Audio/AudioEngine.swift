import AVFoundation
import Combine
import Foundation

enum PlaybackState {
    case idle, loading, playing, paused
    case error(Error)
}

@MainActor
final class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

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

    private var interruptionObserver: Any?
    private var routeChangeObserver: Any?

    private init() {
        self.player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        setupNotifications()
    }

    func load(url: URL) async {
        state = .loading
        AudioSessionManager.shared.ensureActive()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        playerItem = item

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { [weak self] in
                switch item.status {
                case .readyToPlay:
                    self?.isBuffering = false
                case .failed:
                    if let err = item.error {
                        self?.state = .error(err)
                    }
                default: break
                }
            }
        }

        itemObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { [weak self] in
                self?.isBuffering = item.isPlaybackBufferEmpty
            }
        }

        player.replaceCurrentItem(with: item)
        addTimeObserver()

        Task { @MainActor [weak self] in
            if let dur = try? await asset.load(.duration) {
                self?.duration = dur.seconds.isNaN ? 0 : dur.seconds
            }
        }
    }

    func play() {
        AudioSessionManager.shared.ensureActive()
        player.play()
        if playbackSpeed != 1.0 {
            player.rate = playbackSpeed
        }
        state = .playing
    }

    func pause() {
        player.pause()
        state = .paused
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
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
        state = .idle
        currentTime = 0
        duration = 0
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }

    var onPlaybackEnded: (() -> Void)?
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?

    private func addTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            self.onTimeUpdate?(time.seconds, self.duration)
        }
        NotificationCenter.default.addObserver(self,
            selector: #selector(playerItemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem)
    }

    private func removeTimeObserver() {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    @objc private func playerItemDidFinish() {
        state = .paused
        currentTime = duration
        onPlaybackEnded?()
    }

    private func setupNotifications() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            state = .paused
        case .ended:
            if let optValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optValue)
                if options.contains(.shouldResume) {
                    AudioSessionManager.shared.ensureActive()
                    player.play()
                    if playbackSpeed != 1.0 {
                        player.rate = playbackSpeed
                    }
                    state = .playing
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
        }
    }
}

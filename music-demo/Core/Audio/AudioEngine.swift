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

    private var player: AVPlayer = AVPlayer()
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    private init() {
        setupNotifications()
    }

    func load(url: URL) async {
        state = .loading
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
        player.rate = playbackSpeed
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
        if isPlaying { player.rate = speed }
    }

    var onPlaybackEnded: (() -> Void)?

    private func addTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
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
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            if let optValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optValue)
                if options.contains(.shouldResume) { play() }
            }
        @unknown default: break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable { pause() }
    }
}

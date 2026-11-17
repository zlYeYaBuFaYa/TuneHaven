import AVFoundation
import Foundation

@MainActor
final class AudioSessionManager: AudioSessionManaging {
    static let shared = AudioSessionManager()
    private(set) var isConfigured = false
    private let log = AppLogger.shared

    private init() {}

    /// 启动时调用：只设置类别，不激活会话，打开 App 不会打断其他 App 的音频。
    /// 不改 `isConfigured`，第一次 `ensureActive()` 仍走完整的 `configure()`。
    @discardableResult
    func configureCategory() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            return true
        } catch {
            log.error("configureCategory failed: \(error)")
            return false
        }
    }

    @discardableResult
    func configure() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            isConfigured = true
            return true
        } catch {
            log.error("configure failed: \(error)")
            do {
                try session.setActive(true, options: [])
                isConfigured = true
                return true
            } catch {
                log.error("setActive retry failed: \(error)")
            }
            return false
        }
    }

    @discardableResult
    func ensureActive() -> Bool {
        let session = AVAudioSession.sharedInstance()
        if !isConfigured {
            return configure()
        }
        do {
            if session.category != .playback {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(true, options: [])
            isConfigured = true
            return true
        } catch {
            log.error("ensureActive failed: \(error)")
            return false
        }
    }
}

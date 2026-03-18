import AVFoundation
import Foundation

@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private(set) var isConfigured = false
    private let log = AppLogger.shared

    private init() {}

    @discardableResult
    func configure() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            isConfigured = true
            return true
        } catch {
            log.error("[AudioSessionManager] configure failed: \(error)")
            do {
                try session.setActive(true, options: [])
                isConfigured = true
                return true
            } catch {
                log.error("[AudioSessionManager] setActive retry failed: \(error)")
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
            log.error("[AudioSessionManager] ensureActive failed: \(error)")
            return false
        }
    }
}

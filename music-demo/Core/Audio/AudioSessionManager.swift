import AVFoundation
import Foundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private(set) var isConfigured = false

    private init() {}

    /// Must be called as early as possible — ideally in AppDelegate.didFinishLaunchingWithOptions
    @discardableResult
    func configure() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            isConfigured = true
            return true
        } catch {
            print("[AudioSessionManager] configure failed: \(error)")
            // Category might have been set even if setActive failed; retry activation
            do {
                try session.setCategory(.playback, mode: .default, options: [])
            } catch {
                print("[AudioSessionManager] setCategory retry failed: \(error)")
            }
            return false
        }
    }

    func ensureActive() {
        let session = AVAudioSession.sharedInstance()
        if !isConfigured {
            configure()
        }
        do {
            if session.category != .playback {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(true, options: [])
            isConfigured = true
        } catch {
            print("[AudioSessionManager] ensureActive failed: \(error)")
        }
    }
}

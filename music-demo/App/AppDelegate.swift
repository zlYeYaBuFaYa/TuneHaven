import UIKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        verifyBackgroundAudioEntitlement()
        configureAudioSession()
        application.beginReceivingRemoteControlEvents()
        return true
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            print("[AppDelegate] ✅ Audio session OK — category=\(session.category.rawValue)")
        } catch {
            print("[AppDelegate] ❌ Audio session FAILED: \(error)")
        }
        AudioSessionManager.shared.configure()
    }

    private func verifyBackgroundAudioEntitlement() {
        guard let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] else {
            print("[AppDelegate] ⚠️ UIBackgroundModes NOT FOUND in Info.plist — background audio WILL FAIL")
            return
        }
        if modes.contains("audio") {
            print("[AppDelegate] ✅ UIBackgroundModes contains 'audio'")
        } else {
            print("[AppDelegate] ⚠️ UIBackgroundModes exists but does NOT contain 'audio': \(modes)")
        }
    }
}

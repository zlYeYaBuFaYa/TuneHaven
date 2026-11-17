import UIKit
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        verifyBackgroundAudioEntitlement()
        configureAudioSession()
        configureEarlyAppearance()
        application.beginReceivingRemoteControlEvents()
        return true
    }

    private func configureEarlyAppearance() {
        let registry = ThemeRegistry.shared
        if registry.allThemes.isEmpty { registry.bootstrap() }
        let style = registry.resolveCurrentStyle()

        let bgColor = UIColor(style.palette.background)
        let surfaceColor = UIColor(style.palette.surface)

        // 深浅外观跟随系统，不再按主题强制
        UIWindow.appearance().backgroundColor = bgColor

        Self.applyNavigationBarAppearance(surfaceColor: surfaceColor)
        AppLogger.shared.info("[AppDelegate] configureEarlyAppearance — theme=\(style.id) bg=\(bgColor)")
    }

    static func applyNavigationBarAppearance(surfaceColor: UIColor) {
        LiquidGlassPolicy.applyGlobalNavigationBarAppearance(surfaceColor: surfaceColor)
    }

    private func configureAudioSession() {
        // 只设类别不激活：真正开始播放时由 AudioEngine.play() 激活
        var success = AudioSessionManager.shared.configureCategory()
        if !success {
            AppLogger.shared.error("[AppDelegate] Audio session FAILED, retrying...")
            success = AudioSessionManager.shared.configureCategory()
        }
        AppLogger.shared.info("[AppDelegate] Audio session \(success ? "OK" : "FAILED after retry")")
    }

    private func verifyBackgroundAudioEntitlement() {
        guard let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] else {
            AppLogger.shared.info("[AppDelegate] UIBackgroundModes NOT FOUND in Info.plist")
            return
        }
        if modes.contains("audio") {
            AppLogger.shared.info("[AppDelegate] UIBackgroundModes contains 'audio'")
        } else {
            AppLogger.shared.info("[AppDelegate] UIBackgroundModes missing 'audio': \(modes)")
        }
    }
}

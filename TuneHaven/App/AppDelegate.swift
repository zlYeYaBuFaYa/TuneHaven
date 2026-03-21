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
        let styleId = UserDefaults.standard.string(forKey: "theme_style") ?? "mint_breeze"
        let style = registry.theme(for: styleId) ?? registry.defaultTheme

        let bgColor = UIColor(style.palette.background)
        let surfaceColor = UIColor(style.palette.surface)
        let uiStyle: UIUserInterfaceStyle = style.colorScheme == .dark ? .dark : .light

        UIWindow.appearance().backgroundColor = bgColor
        UIWindow.appearance().overrideUserInterfaceStyle = uiStyle

        Self.applyNavigationBarAppearance(surfaceColor: surfaceColor)
        AppLogger.shared.info("[AppDelegate] configureEarlyAppearance — theme=\(style.id) bg=\(bgColor)")
    }

    static func applyNavigationBarAppearance(surfaceColor: UIColor) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = surfaceColor
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    private func configureAudioSession() {
        let success = AudioSessionManager.shared.configure()
        AppLogger.shared.info("[AppDelegate] Audio session \(success ? "OK" : "FAILED")")
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

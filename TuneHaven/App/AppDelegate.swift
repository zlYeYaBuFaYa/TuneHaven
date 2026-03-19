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

    /// 在窗口创建之前通过 UIAppearance 设置默认背景色 — 这是最早的时机
    private func configureEarlyAppearance() {
        let mode = ColorMode(rawValue: UserDefaults.standard.integer(forKey: AppStorageKey.colorMode)) ?? .system
        let isDark: Bool
        switch mode {
        case .light: isDark = false
        case .dark: isDark = true
        case .system: isDark = UITraitCollection.current.userInterfaceStyle == .dark
        }
        let styleId = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) ?? "meadow_breeze"
        let registry = ThemeRegistry.shared
        registry.bootstrap()
        let style = registry.theme(for: styleId) ?? registry.defaultTheme
        let bgColor = UIColor(isDark ? style.darkPalette.background : style.lightPalette.background)
        let surfaceColor = UIColor(isDark ? style.darkPalette.surface : style.lightPalette.surface)

        UIWindow.appearance().backgroundColor = bgColor

        Self.applyNavigationBarAppearance(surfaceColor: surfaceColor)
        AppLogger.shared.info("[AppDelegate] configureEarlyAppearance — isDark=\(isDark) bg=\(bgColor)")
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
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            AppLogger.shared.info("[AppDelegate] Audio session OK — category=\(session.category.rawValue)")
        } catch {
            AppLogger.shared.info("[AppDelegate] Audio session FAILED: \(error)")
        }
        AudioSessionManager.shared.configure()
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

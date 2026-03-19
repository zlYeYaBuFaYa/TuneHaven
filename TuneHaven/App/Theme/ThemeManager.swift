import SwiftUI

// MARK: - EnvironmentKey

struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.meadowBreeze.lightPalette
}

extension EnvironmentValues {
    var themePalette: ThemeColorPalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

// MARK: - ThemeManager

@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var colorMode: ColorMode
    @Published private(set) var currentStyle: ThemeStyle

    @AppStorage(AppStorageKey.colorMode)   private var storedColorMode: Int = 0
    @AppStorage(AppStorageKey.themeStyle)  private var storedThemeStyle: String = "meadow_breeze"

    private let registry = ThemeRegistry.shared

    private static let legacyThemeMapping: [String: String] = [
        "morandi_green": "meadow_breeze",
        "classic_indigo": "meadow_breeze",
        "sakura_pink": "meadow_breeze",
        "minimal_pure": "meadow_breeze",
        "warm_sunlight": "meadow_breeze",
        "digital_mist": "meadow_breeze"
    ]

    init() {
        registry.bootstrap()

        let mode = ColorMode(rawValue: UserDefaults.standard.integer(forKey: AppStorageKey.colorMode)) ?? .system
        var styleId = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) ?? "meadow_breeze"

        if let migrated = Self.legacyThemeMapping[styleId] {
            styleId = migrated
            UserDefaults.standard.set(migrated, forKey: AppStorageKey.themeStyle)
        }

        colorMode = mode
        currentStyle = registry.theme(for: styleId) ?? registry.defaultTheme
    }

    func setColorMode(_ mode: ColorMode) {
        colorMode = mode
        storedColorMode = mode.rawValue
    }

    func applyToWindows() {
        guard let windowScene = Self.foregroundWindowScene else {
            AppLogger.shared.debug("[ThemeManager] applyToWindows — no foreground windowScene yet")
            return
        }
        let effectiveScheme = effectiveSchemeFromScene(windowScene)
        let palette = effectiveScheme == .dark ? currentStyle.darkPalette : currentStyle.lightPalette
        let bgColor = UIColor(palette.background)
        let surfaceColor = UIColor(palette.surface)

        AppLogger.shared.debug("[ThemeManager] applyToWindows — mode=\(colorMode) scheme=\(effectiveScheme) bgColor=\(bgColor)")

        AppDelegate.applyNavigationBarAppearance(surfaceColor: surfaceColor)

        windowScene.windows.forEach { window in
            window.backgroundColor = bgColor
            Self.setNavigationControllerBackgrounds(on: window.rootViewController, color: bgColor)
        }
    }

    /// 轻量刷新：仅更新已有窗口的背景色，不触碰 trait 或 appearance proxy。
    /// 色彩模式完全由 SwiftUI .preferredColorScheme() 控制。
    func refreshWindows() {
        guard let windowScene = Self.foregroundWindowScene else {
            AppLogger.shared.debug("[ThemeManager] refreshWindows — no foreground windowScene")
            return
        }
        let effectiveScheme = effectiveSchemeFromScene(windowScene)
        let palette = effectiveScheme == .dark ? currentStyle.darkPalette : currentStyle.lightPalette
        let bgColor = UIColor(palette.background)

        windowScene.windows.forEach { window in
            window.backgroundColor = bgColor
        }
        AppLogger.shared.debug("[ThemeManager] refreshWindows done — scheme=\(effectiveScheme)")
    }

    private func effectiveSchemeFromScene(_ windowScene: UIWindowScene) -> ColorScheme {
        switch colorMode {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let style = windowScene.windows.first?.traitCollection.userInterfaceStyle ?? .light
            return style == .dark ? .dark : .light
        }
    }

    private static var foregroundWindowScene: UIWindowScene? {
        let allScenes: [UIWindowScene] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let foreground = allScenes.first {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
        return foreground ?? allScenes.first
    }

    // MARK: - 延后刷新机制

    private var pendingRefreshWork: DispatchWorkItem?
    private var pendingFullApply: Bool = false

    func scheduleWindowRefresh(delay: TimeInterval = 0.05, fullApply: Bool = true) {
        if fullApply { pendingFullApply = true }
        pendingRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pendingFullApply {
                self.applyToWindows()
            } else {
                self.refreshWindows()
            }
            self.pendingFullApply = false
        }
        pendingRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func setNavigationControllerBackgrounds(on vc: UIViewController?, color: UIColor) {
        guard let vc = vc else { return }
        if let nav = vc as? UINavigationController {
            nav.view.backgroundColor = color
            AppLogger.shared.debug("[ThemeManager] set UINavigationController.view.bg = \(color)")
        }
        for child in vc.children {
            setNavigationControllerBackgrounds(on: child, color: color)
        }
        if let presented = vc.presentedViewController {
            setNavigationControllerBackgrounds(on: presented, color: color)
        }
    }

    func setTheme(_ style: ThemeStyle) {
        currentStyle = style
        storedThemeStyle = style.id
        scheduleWindowRefresh(fullApply: true)
    }

    func resolvedPalette(for systemColorScheme: ColorScheme) -> ThemeColorPalette {
        let effective = effectiveColorScheme(system: systemColorScheme)
        return effective == .dark ? currentStyle.darkPalette : currentStyle.lightPalette
    }

    var resolvedColorScheme: ColorScheme? { colorMode.colorScheme }

    private func effectiveColorScheme(system: ColorScheme) -> ColorScheme {
        colorMode.colorScheme ?? system
    }
}

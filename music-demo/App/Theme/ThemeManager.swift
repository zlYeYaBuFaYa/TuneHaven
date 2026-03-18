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

    @AppStorage("color_mode")   private var storedColorMode: Int = 0
    @AppStorage("theme_style")  private var storedThemeStyle: String = "meadow_breeze"

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

        let mode = ColorMode(rawValue: UserDefaults.standard.integer(forKey: "color_mode")) ?? .system
        var styleId = UserDefaults.standard.string(forKey: "theme_style") ?? "meadow_breeze"

        if let migrated = Self.legacyThemeMapping[styleId] {
            styleId = migrated
            UserDefaults.standard.set(migrated, forKey: "theme_style")
        }

        colorMode = mode
        currentStyle = registry.theme(for: styleId) ?? registry.defaultTheme
    }

    func setColorMode(_ mode: ColorMode) {
        colorMode = mode
        storedColorMode = mode.rawValue
        applyToWindows()
    }

    func applyToWindows() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            AppLogger.shared.debug("[ThemeManager] applyToWindows — no windowScene yet")
            return
        }
        let style = colorMode.uiInterfaceStyle
        let effectiveScheme: ColorScheme
        switch colorMode {
        case .light: effectiveScheme = .light
        case .dark: effectiveScheme = .dark
        case .system:
            effectiveScheme = UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
        let palette = effectiveScheme == .dark ? currentStyle.darkPalette : currentStyle.lightPalette
        let bgColor = UIColor(palette.background)
        let surfaceColor = UIColor(palette.surface)

        AppLogger.shared.debug("[ThemeManager] applyToWindows — mode=\(colorMode) scheme=\(effectiveScheme) bgColor=\(bgColor)")

        AppDelegate.applyNavigationBarAppearance(surfaceColor: surfaceColor)
        UIWindow.appearance().backgroundColor = bgColor
        UIWindow.appearance().overrideUserInterfaceStyle = style

        windowScene.windows.forEach { window in
            window.overrideUserInterfaceStyle = style
            window.backgroundColor = bgColor
            Self.setNavigationControllerBackgrounds(on: window.rootViewController, color: bgColor)
        }
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
        applyToWindows()
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

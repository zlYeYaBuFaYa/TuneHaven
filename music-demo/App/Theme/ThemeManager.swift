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

final class ThemeManager: ObservableObject {
    @Published private(set) var colorMode: ColorMode
    @Published private(set) var currentStyle: ThemeStyle

    @AppStorage("color_mode")   private var storedColorMode: Int = 0
    @AppStorage("theme_style")  private var storedThemeStyle: String = "meadow_breeze"

    private let registry = ThemeRegistry.shared

    private static let legacyThemeMapping: [String: String] = [
        "morandi_green": "meadow_breeze",
        "classic_indigo": "meadow_breeze",
        "sakura_pink": "meadow_breeze"
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
    }

    func setTheme(_ style: ThemeStyle) {
        currentStyle = style
        storedThemeStyle = style.id
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

import SwiftUI

// MARK: - EnvironmentKey（TDD Section 8.5）
struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.morandiGreen.lightPalette
}

extension EnvironmentValues {
    var themePalette: ThemeColorPalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

// MARK: - ThemeManager（TDD Section 8.4）
final class ThemeManager: ObservableObject {
    @Published private(set) var colorMode: ColorMode
    @Published private(set) var currentStyle: ThemeStyle

    @AppStorage("color_mode")   private var storedColorMode: Int = 0
    @AppStorage("theme_style")  private var storedThemeStyle: String = "morandi_green"

    init() {
        let mode = ColorMode(rawValue: UserDefaults.standard.integer(forKey: "color_mode")) ?? .system
        let styleId = UserDefaults.standard.string(forKey: "theme_style") ?? "morandi_green"
        colorMode   = mode
        currentStyle = ThemeStyle.allStyles.first(where: { $0.id == styleId }) ?? .morandiGreen
    }

    func setColorMode(_ mode: ColorMode) {
        colorMode = mode
        storedColorMode = mode.rawValue
    }

    func setTheme(_ style: ThemeStyle) {
        currentStyle = style
        storedThemeStyle = style.id
    }

    /// 根据当前 colorMode + 传入的系统 colorScheme 返回实际色板
    func resolvedPalette(for systemColorScheme: ColorScheme) -> ThemeColorPalette {
        let effective = effectiveColorScheme(system: systemColorScheme)
        return effective == .dark ? currentStyle.darkPalette : currentStyle.lightPalette
    }

    /// 提供给 `.preferredColorScheme()` 的值
    var resolvedColorScheme: ColorScheme? { colorMode.colorScheme }

    private func effectiveColorScheme(system: ColorScheme) -> ColorScheme {
        colorMode.colorScheme ?? system
    }
}

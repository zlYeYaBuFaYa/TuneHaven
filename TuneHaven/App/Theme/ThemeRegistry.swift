import Foundation

/// 主题注册表 — 管理所有可用主题的注册与查找
/// 新增主题只需：1) 创建 ThemeStyle+XXX.swift  2) 在 bootstrap() 中 register
@MainActor
final class ThemeRegistry {
    static let shared = ThemeRegistry()

    private var themes: [ThemeStyle] = []

    private init() {}

    func bootstrap() {
        let defaults: [ThemeStyle] = [.cloudWhite, .azureSky, .twilightRose, .cosmicTech]
        for style in defaults {
            guard !themes.contains(where: { $0.id == style.id }) else { continue }
            themes.append(style)
        }
    }

    var allThemes: [ThemeStyle] {
        themes
    }

    var defaultTheme: ThemeStyle { .cloudWhite }

    func register(_ style: ThemeStyle) {
        guard !themes.contains(where: { $0.id == style.id }) else { return }
        themes.append(style)
    }

    func theme(for id: String) -> ThemeStyle? {
        themes.first { $0.id == id }
    }

    func resolveCurrentStyle() -> ThemeStyle {
        let styleId = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) ?? defaultTheme.id
        return theme(for: styleId) ?? defaultTheme
    }

    #if DEBUG
    func reset() {
        themes.removeAll()
    }
    #endif
}

import Foundation

/// 主题注册表 — 管理所有可用主题的注册与查找
/// 新增主题只需：1) 创建 ThemeStyle+XXX.swift  2) 在 bootstrap() 中 register
final class ThemeRegistry {
    static let shared = ThemeRegistry()

    private var themes: [ThemeStyle] = []

    private init() {}

    func bootstrap() {
        register(.mintBreeze)
        register(.deepOcean)
        register(.cyberNeon)
        register(.glacierBlue)
        register(.auroraDream)
        register(.midnightGold)
    }

    var allThemes: [ThemeStyle] { themes }

    var defaultTheme: ThemeStyle { .mintBreeze }

    func register(_ style: ThemeStyle) {
        guard !themes.contains(where: { $0.id == style.id }) else { return }
        themes.append(style)
    }

    func theme(for id: String) -> ThemeStyle? {
        themes.first { $0.id == id }
    }

    func reset() {
        themes.removeAll()
    }
}

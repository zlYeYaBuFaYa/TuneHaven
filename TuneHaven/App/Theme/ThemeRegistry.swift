import Foundation

/// 主题注册表 — 管理所有可用主题的注册与查找
/// 新增主题只需：1) 创建 ThemeStyle+XXX.swift  2) 在 bootstrap() 中 register
final class ThemeRegistry: @unchecked Sendable {
    static let shared = ThemeRegistry()

    private var themes: [ThemeStyle] = []
    private let lock = NSLock()

    private init() {}

    func bootstrap() {
        lock.lock()
        defer { lock.unlock() }
        let defaults: [ThemeStyle] = [.cloudWhite, .azureSky, .twilightRose, .cosmicTech]
        for style in defaults {
            guard !themes.contains(where: { $0.id == style.id }) else { continue }
            themes.append(style)
        }
    }

    var allThemes: [ThemeStyle] {
        lock.lock()
        defer { lock.unlock() }
        return themes
    }

    var defaultTheme: ThemeStyle { .cloudWhite }

    func register(_ style: ThemeStyle) {
        lock.lock()
        defer { lock.unlock() }
        guard !themes.contains(where: { $0.id == style.id }) else { return }
        themes.append(style)
    }

    func theme(for id: String) -> ThemeStyle? {
        lock.lock()
        defer { lock.unlock() }
        return themes.first { $0.id == id }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        themes.removeAll()
    }
}

import Foundation

/// 主题注册表 — 管理所有可用主题的注册与查找
/// 新增主题只需：1) 创建 ThemeStyle+XXX.swift  2) 在 bootstrap() 中 register
@MainActor
final class ThemeRegistry {
    static let shared = ThemeRegistry()

    private var themes: [ThemeStyle] = []

    private init() {}

    func bootstrap() {
        let defaults: [ThemeStyle] = [.cloudHaze, .clearIsle, .moonHalo]
        for style in defaults {
            guard !themes.contains(where: { $0.id == style.id }) else { continue }
            themes.append(style)
        }
    }

    var allThemes: [ThemeStyle] {
        themes
    }

    var defaultTheme: ThemeStyle { .cloudHaze }

    /// 旧主题 ID → 新主题 ID。旧偏好与旧备份中的 ID 都经这里换算，不会落回默认主题。
    static let legacyThemeIDs: [String: String] = [
        "cloud_white": "cloud_haze",
        "azure_sky": "clear_isle",
        "twilight_rose": "cloud_haze",
        "cosmic_tech": "moon_halo",
    ]

    /// 把存储的主题 ID 换成当前可用的 ID；无法识别时返回 nil
    func canonicalID(for raw: String) -> String? {
        let id = Self.legacyThemeIDs[raw] ?? raw
        return theme(for: id)?.id
    }

    func register(_ style: ThemeStyle) {
        guard !themes.contains(where: { $0.id == style.id }) else { return }
        themes.append(style)
    }

    func theme(for id: String) -> ThemeStyle? {
        themes.first { $0.id == id }
    }

    func resolveCurrentStyle() -> ThemeStyle {
        let raw = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) ?? defaultTheme.id
        return canonicalID(for: raw).flatMap(theme(for:)) ?? defaultTheme
    }

    #if DEBUG
    func reset() {
        themes.removeAll()
    }
    #endif
}

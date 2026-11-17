import SwiftUI

// MARK: - 主题背景类型

enum ThemeBackgroundType: Equatable {
    case solidColor
    /// 不透明底色上叠三束低频柔光（docs/UI设计文档.md §6.1）
    case softGlow
    case userWallpaper
}

// MARK: - 主题卡片风格

enum ThemeCardStyle: String {
    case standard
    case rounded
    case glassmorphism
    case minimal
    case softFloat
    case frosted
}

// MARK: - 主题字体风格

enum ThemeFontStyle: String {
    case system
    case rounded
    case monospaced
    case serif
}

// MARK: - 卡片渲染参数

struct ThemeCardConfig: Equatable {
    let cornerRadius: CGFloat
    let backgroundOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let shadowOpacity: Double
    let borderWidth: CGFloat
    let borderOpacity: Double

    static let standard      = ThemeCardConfig(cornerRadius: 10, backgroundOpacity: 1.0, shadowRadius: 0, shadowY: 0, shadowOpacity: 0, borderWidth: 0, borderOpacity: 0)
    static let rounded       = ThemeCardConfig(cornerRadius: 16, backgroundOpacity: 0.9, shadowRadius: 0, shadowY: 0, shadowOpacity: 0, borderWidth: 1.5, borderOpacity: 0.15)
    static let glassmorphism = ThemeCardConfig(cornerRadius: 12, backgroundOpacity: 1.0, shadowRadius: 8, shadowY: 2, shadowOpacity: 0.08, borderWidth: 0.5, borderOpacity: 0.2)
    static let minimal       = ThemeCardConfig(cornerRadius: 6, backgroundOpacity: 0.7, shadowRadius: 0, shadowY: 0, shadowOpacity: 0, borderWidth: 0, borderOpacity: 0)
    static let softFloat     = ThemeCardConfig(cornerRadius: 14, backgroundOpacity: 0.85, shadowRadius: 12, shadowY: 4, shadowOpacity: 0.1, borderWidth: 0, borderOpacity: 0)
    static let frosted       = ThemeCardConfig(cornerRadius: 10, backgroundOpacity: 1.0, shadowRadius: 0, shadowY: 0, shadowOpacity: 0, borderWidth: 0.5, borderOpacity: 0.3)
}

// MARK: - 完整视觉配置

struct ThemeVisualConfig {
    let backgroundType: ThemeBackgroundType
    let cardStyle: ThemeCardStyle
    let cardConfig: ThemeCardConfig
    let fontStyle: ThemeFontStyle
    let contentOverlayOpacity: Double
    let navigationBarBlur: Bool
    let tabBarBlur: Bool
}

extension ThemeVisualConfig {
    /// 三套主题共用：柔光背景、轻填充卡片、系统字体
    static let softGlow = ThemeVisualConfig(
        backgroundType: .softGlow,
        cardStyle: .softFloat,
        cardConfig: .softFloat,
        fontStyle: .system,
        contentOverlayOpacity: 0,
        navigationBarBlur: true,
        tabBarBlur: true
    )
}

// MARK: - hasCustomBackground（保留 computed property）

extension ThemeStyle {
    var hasCustomBackground: Bool {
        visualConfig.backgroundType != .solidColor
    }
}

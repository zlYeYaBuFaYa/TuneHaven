import SwiftUI

// MARK: - 主题背景类型

enum ThemeBackgroundType: Equatable {
    case solidColor
    case codeGenerated(ThemePatternType)
    case userWallpaper
}

enum ThemePatternType: String, Equatable {
    case mintLeaves
    case oceanBubbles
    case cyberParticles
    case glacierCrystals
    case auroraWaves
    case goldDust
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

// MARK: - 完整视觉配置

struct ThemeVisualConfig {
    let backgroundType: ThemeBackgroundType
    let cardStyle: ThemeCardStyle
    let fontStyle: ThemeFontStyle
    let contentOverlayOpacity: Double
    let navigationBarBlur: Bool
    let tabBarBlur: Bool
}

// MARK: - hasCustomBackground（保留 computed property）

extension ThemeStyle {
    var hasCustomBackground: Bool {
        visualConfig.backgroundType != .solidColor
    }
}

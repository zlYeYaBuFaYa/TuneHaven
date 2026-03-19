import SwiftUI

// MARK: - 主题背景类型

enum ThemeBackgroundType: Equatable {
    case solidColor
    case codeGenerated(ThemePatternType)
    case userWallpaper
}

enum ThemePatternType: String, Equatable {
    case comicSky
    case techGrid
    case inkMountain
    case rosePetal
    case frostAurora
    case spaceNeon
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

extension ThemeVisualConfig {
    static let solidDefault = ThemeVisualConfig(
        backgroundType: .solidColor,
        cardStyle: .standard,
        fontStyle: .system,
        contentOverlayOpacity: 0,
        navigationBarBlur: false,
        tabBarBlur: false
    )

    static let comicPop = ThemeVisualConfig(
        backgroundType: .codeGenerated(.comicSky),
        cardStyle: .rounded,
        fontStyle: .rounded,
        contentOverlayOpacity: 0.03,
        navigationBarBlur: true,
        tabBarBlur: true
    )

    static let crimsonTech = ThemeVisualConfig(
        backgroundType: .codeGenerated(.techGrid),
        cardStyle: .glassmorphism,
        fontStyle: .monospaced,
        contentOverlayOpacity: 0.05,
        navigationBarBlur: true,
        tabBarBlur: true
    )

    static let inkWash = ThemeVisualConfig(
        backgroundType: .codeGenerated(.inkMountain),
        cardStyle: .minimal,
        fontStyle: .serif,
        contentOverlayOpacity: 0.02,
        navigationBarBlur: true,
        tabBarBlur: true
    )

    static let roseDream = ThemeVisualConfig(
        backgroundType: .codeGenerated(.rosePetal),
        cardStyle: .softFloat,
        fontStyle: .rounded,
        contentOverlayOpacity: 0.02,
        navigationBarBlur: true,
        tabBarBlur: true
    )

    static let frostElegance = ThemeVisualConfig(
        backgroundType: .codeGenerated(.frostAurora),
        cardStyle: .frosted,
        fontStyle: .system,
        contentOverlayOpacity: 0.03,
        navigationBarBlur: true,
        tabBarBlur: true
    )

    static let deepSpaceNeon = ThemeVisualConfig(
        backgroundType: .codeGenerated(.spaceNeon),
        cardStyle: .glassmorphism,
        fontStyle: .system,
        contentOverlayOpacity: 0.04,
        navigationBarBlur: true,
        tabBarBlur: true
    )
}

// MARK: - ThemeStyle 视觉配置扩展

extension ThemeStyle {
    var visualConfig: ThemeVisualConfig {
        switch id {
        case "comic_pop":       return .comicPop
        case "crimson_tech":    return .crimsonTech
        case "ink_wash":        return .inkWash
        case "rose_dream":      return .roseDream
        case "frost_elegance":  return .frostElegance
        case "deep_space_neon": return .deepSpaceNeon
        default:                return .solidDefault
        }
    }

    var hasCustomBackground: Bool {
        visualConfig.backgroundType != .solidColor
    }
}

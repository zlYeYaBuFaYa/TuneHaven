import SwiftUI
import UIKit

/// 完整的主题色板
struct ThemeColorPalette {
    // MARK: - 核心色
    let primary: Color
    let primaryDark: Color
    let primaryLight: Color
    let background: Color
    let surface: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let separator: Color

    // MARK: - 扩展色
    let secondary: Color
    let accent: Color
    let highlight: Color
    let gradientStart: Color
    let gradientEnd: Color

    // MARK: - 播放器专用色
    let playerBackground: Color
    let playerText: Color
    let playerSubtext: Color
    let progressBackground: Color

    // MARK: - 图标
    let iconSecondary: Color

    // MARK: - 标签
    let tagBackground: Color
    let tagText: Color

    // MARK: - 对比色
    let onPrimary: Color

    // MARK: - Spotify 升级新增
    let elevatedSurface: Color
    let cardShadow: Color
    let miniPlayerBg: Color
    let hoverHighlight: Color
}

// MARK: - 语义色（所有主题共享，参考 TDD Section 8.2）
enum SemanticColor {
    /// 浅色压深红，浅底上达到 4.5:1。`danger(for: .light)` 固定返回它。
    private static let dangerLightUIColor = uiColor(hex: 0xC62828)
    private static let dangerLight = Color(uiColor: dangerLightUIColor)
    /// 改前的静态红 `#EF4444`。暗色主题恢复这个值。
    private static let dangerOnDarkUIColor = uiColor(hex: 0xEF4444)

    /// 浅色 `#C62828`，暗色 `#EF4444`。未指定深浅时用浅色。
    static let danger = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dangerOnDarkUIColor : dangerLightUIColor
    })
    static let warning = Color(hex: "#F59E0B")  // amber-500
    static let success = Color(hex: "#10B981")  // emerald-500
    static let info    = Color(hex: "#3B82F6")  // blue-500

    // Dark mode variants. 付费墙用的暗色红仍是 dangerDark，不跟随静态 danger。
    static let dangerDark  = Color(hex: "#FB7185")
    static let warningDark = Color(hex: "#FBBF24")
    static let successDark = Color(hex: "#34D399")
    static let infoDark    = Color(hex: "#60A5FA")

    static func danger(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dangerDark : dangerLight
    }

    private static func uiColor(hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

import SwiftUI

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
}

// MARK: - 语义色（所有主题共享，参考 TDD Section 8.2）
enum SemanticColor {
    static let danger  = Color(hex: "#EF4444")  // rose-500
    static let warning = Color(hex: "#F59E0B")  // amber-500
    static let success = Color(hex: "#10B981")  // emerald-500
    static let info    = Color(hex: "#3B82F6")  // blue-500

    // Dark mode variants
    static let dangerDark  = Color(hex: "#FB7185")
    static let warningDark = Color(hex: "#FBBF24")
    static let successDark = Color(hex: "#34D399")
}

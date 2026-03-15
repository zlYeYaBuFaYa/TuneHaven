import SwiftUI

/// 主题风格定义（含 Light/Dark 双色板）
struct ThemeStyle: Identifiable {
    let id: String
    let displayName: String
    let previewColor: Color
    let lightPalette: ThemeColorPalette
    let darkPalette: ThemeColorPalette
}

// MARK: - 默认主题：翠野清风

extension ThemeStyle {

    static let meadowBreeze = ThemeStyle(
        id: "meadow_breeze",
        displayName: "翠野清风",
        previewColor: Color(hex: "#10B981"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#10B981"),
            primaryDark:        Color(hex: "#059669"),
            primaryLight:       Color(hex: "#A7F3D0"),
            background:         Color(hex: "#FAFAF9"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#F3F4F6"),
            textPrimary:        Color(hex: "#1F2937"),
            textSecondary:      Color(hex: "#6B7280"),
            textTertiary:       Color(hex: "#9CA3AF"),
            separator:          Color(hex: "#E5E7EB"),
            secondary:          Color(hex: "#6EE7B7"),
            accent:             Color(hex: "#34D399"),
            highlight:          Color(hex: "#D1FAE5"),
            gradientStart:      Color(hex: "#10B981"),
            gradientEnd:        Color(hex: "#059669"),
            playerBackground:   Color(hex: "#1A1A2E"),
            playerText:         Color(hex: "#F9FAFB"),
            playerSubtext:      Color(hex: "#D1D5DB"),
            progressBackground: Color(hex: "#374151"),
            iconSecondary:      Color(hex: "#9CA3AF"),
            tagBackground:      Color(hex: "#D1FAE5"),
            tagText:            Color(hex: "#065F46")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#34D399"),
            primaryDark:        Color(hex: "#10B981"),
            primaryLight:       Color(hex: "#065F46"),
            background:         Color(hex: "#1C1917"),
            surface:            Color(hex: "#292524"),
            surfaceSecondary:   Color(hex: "#3B3532"),
            textPrimary:        Color(hex: "#E7E5E4"),
            textSecondary:      Color(hex: "#A8A29E"),
            textTertiary:       Color(hex: "#78716C"),
            separator:          Color(hex: "#3B3532"),
            secondary:          Color(hex: "#6EE7B7"),
            accent:             Color(hex: "#34D399"),
            highlight:          Color(hex: "#064E3B"),
            gradientStart:      Color(hex: "#34D399"),
            gradientEnd:        Color(hex: "#10B981"),
            playerBackground:   Color(hex: "#0D0D1A"),
            playerText:         Color(hex: "#F9FAFB"),
            playerSubtext:      Color(hex: "#A8A29E"),
            progressBackground: Color(hex: "#1C1917"),
            iconSecondary:      Color(hex: "#78716C"),
            tagBackground:      Color(hex: "#064E3B"),
            tagText:            Color(hex: "#6EE7B7")
        )
    )
}

import SwiftUI

/// 主题风格定义（含 Light/Dark 双色板），对应 TDD Section 8.3
struct ThemeStyle: Identifiable {
    let id: String
    let displayName: String
    let previewColor: Color
    let lightPalette: ThemeColorPalette
    let darkPalette: ThemeColorPalette
}

// MARK: - 内置主题

extension ThemeStyle {

    // v1.0 默认主题：莫兰迪绿
    static let morandiGreen = ThemeStyle(
        id: "morandi_green",
        displayName: "莫兰迪绿（默认）",
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
            playerBackground:   Color(hex: "#0D0D1A"),
            playerText:         Color(hex: "#F9FAFB"),
            playerSubtext:      Color(hex: "#A8A29E"),
            progressBackground: Color(hex: "#1C1917"),
            iconSecondary:      Color(hex: "#78716C"),
            tagBackground:      Color(hex: "#064E3B"),
            tagText:            Color(hex: "#6EE7B7")
        )
    )

    // v2.0 预留：经典蓝
    static let classicIndigo = ThemeStyle(
        id: "classic_indigo",
        displayName: "经典蓝",
        previewColor: Color(hex: "#6366F1"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#6366F1"),
            primaryDark:        Color(hex: "#4F46E5"),
            primaryLight:       Color(hex: "#C7D2FE"),
            background:         Color(hex: "#FAFAFA"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#F3F4F6"),
            textPrimary:        Color(hex: "#1E1B4B"),
            textSecondary:      Color(hex: "#6B7280"),
            textTertiary:       Color(hex: "#9CA3AF"),
            separator:          Color(hex: "#E5E7EB"),
            playerBackground:   Color(hex: "#0F0D1A"),
            playerText:         Color(hex: "#E0E7FF"),
            playerSubtext:      Color(hex: "#A5B4FC"),
            progressBackground: Color(hex: "#312E81"),
            iconSecondary:      Color(hex: "#9CA3AF"),
            tagBackground:      Color(hex: "#EEF2FF"),
            tagText:            Color(hex: "#3730A3")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#818CF8"),
            primaryDark:        Color(hex: "#6366F1"),
            primaryLight:       Color(hex: "#312E81"),
            background:         Color(hex: "#0F0D1A"),
            surface:            Color(hex: "#1E1B2E"),
            surfaceSecondary:   Color(hex: "#2D2A44"),
            textPrimary:        Color(hex: "#E0E7FF"),
            textSecondary:      Color(hex: "#A5B4FC"),
            textTertiary:       Color(hex: "#6366F1"),
            separator:          Color(hex: "#2D2A44"),
            playerBackground:   Color(hex: "#08060F"),
            playerText:         Color(hex: "#E0E7FF"),
            playerSubtext:      Color(hex: "#818CF8"),
            progressBackground: Color(hex: "#1E1B2E"),
            iconSecondary:      Color(hex: "#6366F1"),
            tagBackground:      Color(hex: "#1E1B4B"),
            tagText:            Color(hex: "#C7D2FE")
        )
    )

    // v2.0 预留：樱花粉
    static let sakuraPink = ThemeStyle(
        id: "sakura_pink",
        displayName: "樱花粉",
        previewColor: Color(hex: "#F472B6"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#EC4899"),
            primaryDark:        Color(hex: "#DB2777"),
            primaryLight:       Color(hex: "#FBCFE8"),
            background:         Color(hex: "#FFFBFE"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#FDF2F8"),
            textPrimary:        Color(hex: "#3B0A2A"),
            textSecondary:      Color(hex: "#78716C"),
            textTertiary:       Color(hex: "#A8A29E"),
            separator:          Color(hex: "#FCE7F3"),
            playerBackground:   Color(hex: "#1A0A12"),
            playerText:         Color(hex: "#FDF2F8"),
            playerSubtext:      Color(hex: "#F9A8D4"),
            progressBackground: Color(hex: "#831843"),
            iconSecondary:      Color(hex: "#A8A29E"),
            tagBackground:      Color(hex: "#FCE7F3"),
            tagText:            Color(hex: "#9D174D")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#F472B6"),
            primaryDark:        Color(hex: "#EC4899"),
            primaryLight:       Color(hex: "#831843"),
            background:         Color(hex: "#1A0A12"),
            surface:            Color(hex: "#2A1520"),
            surfaceSecondary:   Color(hex: "#3D1F2E"),
            textPrimary:        Color(hex: "#FDF2F8"),
            textSecondary:      Color(hex: "#F9A8D4"),
            textTertiary:       Color(hex: "#BE185D"),
            separator:          Color(hex: "#3D1F2E"),
            playerBackground:   Color(hex: "#0D0508"),
            playerText:         Color(hex: "#FDF2F8"),
            playerSubtext:      Color(hex: "#F9A8D4"),
            progressBackground: Color(hex: "#1A0A12"),
            iconSecondary:      Color(hex: "#BE185D"),
            tagBackground:      Color(hex: "#500724"),
            tagText:            Color(hex: "#FBCFE8")
        )
    )

    /// v1.0 注册的主题（TDD 说 v1.0 仅注册默认主题，但我们直接注册全部方便演示）
    static let allStyles: [ThemeStyle] = [.morandiGreen, .classicIndigo, .sakuraPink]
}

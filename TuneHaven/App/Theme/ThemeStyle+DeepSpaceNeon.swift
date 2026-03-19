import SwiftUI

// MARK: - 深空霓虹（赛博科技风）

extension ThemeStyle {

    static let deepSpaceNeon = ThemeStyle(
        id: "deep_space_neon",
        displayName: "深空霓虹",
        previewColor: Color(hex: "#00D4FF"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#0891B2"),
            primaryDark:        Color(hex: "#0E7490"),
            primaryLight:       Color(hex: "#CFFAFE"),
            background:         Color(hex: "#F0F9FF"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#E0F2FE"),
            textPrimary:        Color(hex: "#0C4A6E"),
            textSecondary:      Color(hex: "#475569"),
            textTertiary:       Color(hex: "#94A3B8"),
            separator:          Color(hex: "#BAE6FD"),
            secondary:          Color(hex: "#22D3EE"),
            accent:             Color(hex: "#7C3AED"),
            highlight:          Color(hex: "#E0F2FE"),
            gradientStart:      Color(hex: "#0891B2"),
            gradientEnd:        Color(hex: "#0284C7"),
            playerBackground:   Color(hex: "#050810"),
            playerText:         Color(hex: "#F8FAFC"),
            playerSubtext:      Color(hex: "#94A3B8"),
            progressBackground: Color(hex: "#1E293B"),
            iconSecondary:      Color(hex: "#94A3B8"),
            tagBackground:      Color(hex: "#E0F2FE"),
            tagText:            Color(hex: "#0E7490")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#00D4FF"),
            primaryDark:        Color(hex: "#0284C7"),
            primaryLight:       Color(hex: "#0C2D3D"),
            background:         Color(hex: "#080C18"),
            surface:            Color(hex: "#131B2D"),
            surfaceSecondary:   Color(hex: "#1A2340"),
            textPrimary:        Color(hex: "#F1F5F9"),
            textSecondary:      Color(hex: "#94A3B8"),
            textTertiary:       Color(hex: "#475569"),
            separator:          Color(hex: "#1E293B"),
            secondary:          Color(hex: "#67E8F9"),
            accent:             Color(hex: "#7C3AED"),
            highlight:          Color(hex: "#0C2D3D"),
            gradientStart:      Color(hex: "#00D4FF"),
            gradientEnd:        Color(hex: "#0284C7"),
            playerBackground:   Color(hex: "#050810"),
            playerText:         Color(hex: "#F8FAFC"),
            playerSubtext:      Color(hex: "#94A3B8"),
            progressBackground: Color(hex: "#1E293B"),
            iconSecondary:      Color(hex: "#64748B"),
            tagBackground:      Color(hex: "#0C2D3D"),
            tagText:            Color(hex: "#67E8F9")
        )
    )
}

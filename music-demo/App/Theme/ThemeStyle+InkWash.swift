import SwiftUI

// MARK: - 水墨丹青（雅致墨白风）

extension ThemeStyle {

    static let inkWash = ThemeStyle(
        id: "ink_wash",
        displayName: "水墨丹青",
        previewColor: Color(hex: "#3A3A3A"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#3A3A3A"),
            primaryDark:        Color(hex: "#1A1A1A"),
            primaryLight:       Color(hex: "#D0D0D0"),
            background:         Color(hex: "#F8F7F5"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#F0EFED"),
            textPrimary:        Color(hex: "#1A1A1A"),
            textSecondary:      Color(hex: "#666666"),
            textTertiary:       Color(hex: "#999999"),
            separator:          Color(hex: "#E0DFDD"),
            secondary:          Color(hex: "#666666"),
            accent:             Color(hex: "#4A4A4A"),
            highlight:          Color(hex: "#EEEDEB"),
            gradientStart:      Color(hex: "#3A3A3A"),
            gradientEnd:        Color(hex: "#666666"),
            playerBackground:   Color(hex: "#0A0A0A"),
            playerText:         Color(hex: "#F0F0F0"),
            playerSubtext:      Color(hex: "#999999"),
            progressBackground: Color(hex: "#2A2A2A"),
            iconSecondary:      Color(hex: "#999999"),
            tagBackground:      Color(hex: "#EEEDEB"),
            tagText:            Color(hex: "#3A3A3A")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#D0D0D0"),
            primaryDark:        Color(hex: "#A0A0A0"),
            primaryLight:       Color(hex: "#333333"),
            background:         Color(hex: "#0E0E0E"),
            surface:            Color(hex: "#1A1A1A"),
            surfaceSecondary:   Color(hex: "#252525"),
            textPrimary:        Color(hex: "#E8E8E8"),
            textSecondary:      Color(hex: "#A0A0A0"),
            textTertiary:       Color(hex: "#666666"),
            separator:          Color(hex: "#2A2A2A"),
            secondary:          Color(hex: "#B0B0B0"),
            accent:             Color(hex: "#C0C0C0"),
            highlight:          Color(hex: "#252525"),
            gradientStart:      Color(hex: "#D0D0D0"),
            gradientEnd:        Color(hex: "#B0B0B0"),
            playerBackground:   Color(hex: "#050505"),
            playerText:         Color(hex: "#E8E8E8"),
            playerSubtext:      Color(hex: "#A0A0A0"),
            progressBackground: Color(hex: "#1A1A1A"),
            iconSecondary:      Color(hex: "#666666"),
            tagBackground:      Color(hex: "#252525"),
            tagText:            Color(hex: "#D0D0D0")
        )
    )
}

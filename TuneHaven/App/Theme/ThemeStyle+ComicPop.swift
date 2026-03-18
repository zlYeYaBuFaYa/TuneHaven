import SwiftUI

// MARK: - 漫彩波普（活力漫画风）

extension ThemeStyle {

    static let comicPop = ThemeStyle(
        id: "comic_pop",
        displayName: "漫彩波普",
        previewColor: Color(hex: "#FF6D00"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#FF6D00"),
            primaryDark:        Color(hex: "#E65100"),
            primaryLight:       Color(hex: "#FFE0B2"),
            background:         Color(hex: "#FFFAF5"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#FFF3E0"),
            textPrimary:        Color(hex: "#2D2D2D"),
            textSecondary:      Color(hex: "#757575"),
            textTertiary:       Color(hex: "#A0A0A0"),
            separator:          Color(hex: "#F0E0D0"),
            secondary:          Color(hex: "#FFAB40"),
            accent:             Color(hex: "#FF9100"),
            highlight:          Color(hex: "#FFF3E0"),
            gradientStart:      Color(hex: "#FF6D00"),
            gradientEnd:        Color(hex: "#FFAB40"),
            playerBackground:   Color(hex: "#1A1208"),
            playerText:         Color(hex: "#FFF8F0"),
            playerSubtext:      Color(hex: "#A0A0A0"),
            progressBackground: Color(hex: "#3A2A15"),
            iconSecondary:      Color(hex: "#A0A0A0"),
            tagBackground:      Color(hex: "#FFF3E0"),
            tagText:            Color(hex: "#E65100")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#FFAB40"),
            primaryDark:        Color(hex: "#FF6D00"),
            primaryLight:       Color(hex: "#4A3010"),
            background:         Color(hex: "#1A1410"),
            surface:            Color(hex: "#282018"),
            surfaceSecondary:   Color(hex: "#342A1A"),
            textPrimary:        Color(hex: "#F5F0EB"),
            textSecondary:      Color(hex: "#A09080"),
            textTertiary:       Color(hex: "#706050"),
            separator:          Color(hex: "#3A3020"),
            secondary:          Color(hex: "#FFD180"),
            accent:             Color(hex: "#FFAB40"),
            highlight:          Color(hex: "#3A2A10"),
            gradientStart:      Color(hex: "#FFAB40"),
            gradientEnd:        Color(hex: "#FFD180"),
            playerBackground:   Color(hex: "#0D0A05"),
            playerText:         Color(hex: "#F5F0EB"),
            playerSubtext:      Color(hex: "#A09080"),
            progressBackground: Color(hex: "#1A1410"),
            iconSecondary:      Color(hex: "#706050"),
            tagBackground:      Color(hex: "#3A2A10"),
            tagText:            Color(hex: "#FFAB40")
        )
    )
}

import SwiftUI

extension ThemeStyle {
    static let mintBreeze = ThemeStyle(
        id: "mint_breeze",
        displayName: "青云薄荷",
        colorScheme: .light,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#26A69A"),
            primaryDark:        Color(hex: "#00897B"),
            primaryLight:       Color(hex: "#80CBC4"),
            background:         Color(hex: "#F0FDFA"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#E0F2F1"),
            textPrimary:        Color(hex: "#004D40"),
            textSecondary:      Color(hex: "#00796B"),
            textTertiary:       Color(hex: "#80A9A0"),
            separator:          Color(hex: "#D4EFEA"),
            secondary:          Color(hex: "#4DB6AC"),
            accent:             Color(hex: "#4DB6AC"),
            highlight:          Color(hex: "#E0F7FA"),
            gradientStart:      Color(hex: "#E0F7FA"),
            gradientEnd:        Color(hex: "#4DB6AC"),
            playerBackground:   Color(hex: "#004D40"),
            playerText:         Color(hex: "#E0F7FA"),
            playerSubtext:      Color(hex: "#80CBC4"),
            progressBackground: Color(hex: "#00695C"),
            iconSecondary:      Color(hex: "#80A9A0"),
            tagBackground:      Color(hex: "#E0F7FA"),
            tagText:            Color(hex: "#004D40")
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .codeGenerated(.mintLeaves),
            cardStyle: .minimal,
            fontStyle: .system,
            contentOverlayOpacity: 0.0,
            navigationBarBlur: false,
            tabBarBlur: false
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#B2DFDB"),
            end: Color(hex: "#4DB6AC")
        )
    )
}

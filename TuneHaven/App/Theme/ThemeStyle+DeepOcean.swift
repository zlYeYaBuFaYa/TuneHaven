import SwiftUI

extension ThemeStyle {
    static let deepOcean = ThemeStyle(
        id: "deep_ocean",
        displayName: "深海鲸歌",
        colorScheme: .dark,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#64B5F6"),
            primaryDark:        Color(hex: "#42A5F5"),
            primaryLight:       Color(hex: "#1E3A5F"),
            background:         Color(hex: "#0A192F"),
            surface:            Color(hex: "#112240"),
            surfaceSecondary:   Color(hex: "#172B45"),
            textPrimary:        Color(hex: "#CAF0F8"),
            textSecondary:      Color(hex: "#5C8AB5"),
            textTertiary:       Color(hex: "#3D5A80"),
            separator:          Color(hex: "#1E3A5F"),
            secondary:          Color(hex: "#48BFE3"),
            accent:             Color(hex: "#48BFE3"),
            highlight:          Color(hex: "#1E3A5F"),
            gradientStart:      Color(hex: "#0A192F"),
            gradientEnd:        Color(hex: "#1E3A5F"),
            playerBackground:   Color(hex: "#060E1A"),
            playerText:         Color(hex: "#CAF0F8"),
            playerSubtext:      Color(hex: "#5C8AB5"),
            progressBackground: Color(hex: "#112240"),
            iconSecondary:      Color(hex: "#3D5A80"),
            tagBackground:      Color(hex: "#1E3A5F"),
            tagText:            Color(hex: "#64B5F6")
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .codeGenerated(.oceanBubbles),
            cardStyle: .glassmorphism,
            fontStyle: .system,
            contentOverlayOpacity: 0.03,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#1E3A5F"),
            end: Color(hex: "#48BFE3")
        )
    )
}

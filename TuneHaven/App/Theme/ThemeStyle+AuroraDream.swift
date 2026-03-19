import SwiftUI

extension ThemeStyle {
    static let auroraDream = ThemeStyle(
        id: "aurora_dream",
        displayName: "极光幻境",
        colorScheme: .dark,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#7C4DFF"),
            primaryDark:        Color(hex: "#651FFF"),
            primaryLight:       Color(hex: "#302B63"),
            background:         Color(hex: "#0F0C29"),
            surface:            Color(hex: "#1A1145"),
            surfaceSecondary:   Color(hex: "#24243E"),
            textPrimary:        Color(hex: "#E8EAF6"),
            textSecondary:      Color(hex: "#9FA8DA"),
            textTertiary:       Color(hex: "#7C7CCF"),
            separator:          Color(hex: "#302B63"),
            secondary:          Color(hex: "#B388FF"),
            accent:             Color(hex: "#69F0AE"),
            highlight:          Color(hex: "#1A1145"),
            gradientStart:      Color(hex: "#4776E6"),
            gradientEnd:        Color(hex: "#8E54E9"),
            playerBackground:   Color(hex: "#0A0820"),
            playerText:         Color(hex: "#E8EAF6"),
            playerSubtext:      Color(hex: "#9FA8DA"),
            progressBackground: Color(hex: "#302B63"),
            iconSecondary:      Color(hex: "#7C7CCF"),
            tagBackground:      Color(hex: "#302B63"),
            tagText:            Color(hex: "#B388FF")
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .codeGenerated(.auroraWaves),
            cardStyle: .glassmorphism,
            fontStyle: .system,
            contentOverlayOpacity: 0.03,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#7C4DFF"),
            end: Color(hex: "#8E54E9")
        )
    )
}

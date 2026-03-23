import SwiftUI

extension ThemeStyle {
    static let cosmicTech = ThemeStyle(
        id: "cosmic_tech",
        displayName: "星际穹顶",
        colorScheme: .dark,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#00D4AA"),
            primaryDark:        Color(hex: "#00B894"),
            primaryLight:       Color(hex: "#33E0BE"),
            background:         Color(hex: "#0B0E17"),
            surface:            Color(hex: "#131829"),
            surfaceSecondary:   Color(hex: "#1A2038"),
            textPrimary:        Color(hex: "#E8EAF0"),
            textSecondary:      Color(hex: "#8A90A5"),
            textTertiary:       Color(hex: "#565C75"),
            separator:          Color(hex: "#232842"),
            secondary:          Color(hex: "#2979FF"),
            accent:             Color(hex: "#FF6B8A"),
            highlight:          Color(hex: "#1A2038"),
            gradientStart:      Color(hex: "#00D4AA"),
            gradientEnd:        Color(hex: "#2979FF"),
            playerBackground:   Color(hex: "#080B14"),
            playerText:         Color(hex: "#E8EAF0"),
            playerSubtext:      Color(hex: "#8A90A5"),
            progressBackground: Color(hex: "#232842"),
            iconSecondary:      Color(hex: "#565C75"),
            tagBackground:      Color(hex: "#1A2038"),
            tagText:            Color(hex: "#33E0BE"),
            onPrimary:          .white,
            elevatedSurface:    Color(hex: "#1A2038"),
            cardShadow:         Color.black.opacity(0.35),
            miniPlayerBg:       Color(hex: "#0B0E17").opacity(0.92),
            hoverHighlight:     Color(hex: "#00D4AA").opacity(0.08)
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .codeGenerated(.cosmicParticles),
            cardStyle: .glassmorphism,
            cardConfig: .glassmorphism,
            fontStyle: .system,
            contentOverlayOpacity: 0.0,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#00D4AA"),
            end: Color(hex: "#2979FF")
        )
    )
}

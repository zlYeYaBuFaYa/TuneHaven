import SwiftUI

extension ThemeStyle {
    static let twilightRose = ThemeStyle(
        id: "twilight_rose",
        displayName: "暮光玫瑰",
        colorScheme: .dark,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#E87B8A"),
            primaryDark:        Color(hex: "#D0606E"),
            primaryLight:       Color(hex: "#F2A8B0"),
            background:         Color(hex: "#1A1520"),
            surface:            Color(hex: "#221A28"),
            surfaceSecondary:   Color(hex: "#2A1E30"),
            textPrimary:        Color(hex: "#F0E0E2"),
            textSecondary:      Color(hex: "#A08A92"),
            textTertiary:       Color(hex: "#6B5A65"),
            separator:          Color(hex: "#352840"),
            secondary:          Color(hex: "#C96878"),
            accent:             Color(hex: "#E87B8A"),
            highlight:          Color(hex: "#2A1E30"),
            gradientStart:      Color(hex: "#E87B8A"),
            gradientEnd:        Color(hex: "#F2A8B0"),
            playerBackground:   Color(hex: "#18121C"),
            playerText:         Color(hex: "#F0E0E2"),
            playerSubtext:      Color(hex: "#A08A92"),
            progressBackground: Color(hex: "#352840"),
            iconSecondary:      Color(hex: "#6B5A65"),
            tagBackground:      Color(hex: "#2A1E30"),
            tagText:            Color(hex: "#F2A8B0"),
            onPrimary:          .white,
            elevatedSurface:    Color(hex: "#2A1E30"),
            cardShadow:         Color.black.opacity(0.30),
            miniPlayerBg:       Color(hex: "#1A1520").opacity(0.92),
            hoverHighlight:     Color(hex: "#E87B8A").opacity(0.08)
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .solidColor,
            cardStyle: .glassmorphism,
            fontStyle: .system,
            contentOverlayOpacity: 0.0,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#E87B8A"),
            end: Color(hex: "#F2A8B0")
        )
    )
}

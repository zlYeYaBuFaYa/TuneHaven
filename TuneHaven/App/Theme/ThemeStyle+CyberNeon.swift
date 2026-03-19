import SwiftUI

extension ThemeStyle {
    static let cyberNeon = ThemeStyle(
        id: "cyber_neon",
        displayName: "赛博霓虹",
        colorScheme: .dark,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#00F5FF"),
            primaryDark:        Color(hex: "#00C8D4"),
            primaryLight:       Color(hex: "#150050"),
            background:         Color(hex: "#0D0221"),
            surface:            Color(hex: "#150050"),
            surfaceSecondary:   Color(hex: "#1A1A3E"),
            textPrimary:        Color(hex: "#E0E0FF"),
            textSecondary:      Color(hex: "#8888CC"),
            textTertiary:       Color(hex: "#5555AA"),
            separator:          Color(hex: "#1A1A3E"),
            secondary:          Color(hex: "#BD00FF"),
            accent:             Color(hex: "#BD00FF"),
            highlight:          Color(hex: "#150050"),
            gradientStart:      Color(hex: "#00F5FF"),
            gradientEnd:        Color(hex: "#BD00FF"),
            playerBackground:   Color(hex: "#080015"),
            playerText:         Color(hex: "#E0E0FF"),
            playerSubtext:      Color(hex: "#8888CC"),
            progressBackground: Color(hex: "#150050"),
            iconSecondary:      Color(hex: "#5555AA"),
            tagBackground:      Color(hex: "#150050"),
            tagText:            Color(hex: "#00F5FF")
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .codeGenerated(.cyberParticles),
            cardStyle: .glassmorphism,
            fontStyle: .monospaced,
            contentOverlayOpacity: 0.04,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#00F5FF"),
            end: Color(hex: "#BD00FF")
        )
    )
}

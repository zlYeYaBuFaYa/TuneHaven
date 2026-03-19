import SwiftUI

extension ThemeStyle {
    static let glacierBlue = ThemeStyle(
        id: "glacier_blue",
        displayName: "冰川幽蓝",
        colorScheme: .light,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#1E88E5"),
            primaryDark:        Color(hex: "#1565C0"),
            primaryLight:       Color(hex: "#BBDEFB"),
            background:         Color(hex: "#F5F9FF"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#E3F2FD"),
            textPrimary:        Color(hex: "#0D47A1"),
            textSecondary:      Color(hex: "#5C6BC0"),
            textTertiary:       Color(hex: "#90A4AE"),
            separator:          Color(hex: "#E3F2FD"),
            secondary:          Color(hex: "#42A5F5"),
            accent:             Color(hex: "#82B1FF"),
            highlight:          Color(hex: "#E3F2FD"),
            gradientStart:      Color(hex: "#BBDEFB"),
            gradientEnd:        Color(hex: "#42A5F5"),
            playerBackground:   Color(hex: "#0D47A1"),
            playerText:         Color(hex: "#E3F2FD"),
            playerSubtext:      Color(hex: "#90CAF9"),
            progressBackground: Color(hex: "#1565C0"),
            iconSecondary:      Color(hex: "#90A4AE"),
            tagBackground:      Color(hex: "#E3F2FD"),
            tagText:            Color(hex: "#1565C0")
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .codeGenerated(.glacierCrystals),
            cardStyle: .frosted,
            fontStyle: .system,
            contentOverlayOpacity: 0.02,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#90CAF9"),
            end: Color(hex: "#1E88E5")
        )
    )
}

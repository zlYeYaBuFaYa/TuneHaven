import SwiftUI

extension ThemeStyle {
    static let midnightGold = ThemeStyle(
        id: "midnight_gold",
        displayName: "夜幕鎏金",
        colorScheme: .dark,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#D4AF37"),
            primaryDark:        Color(hex: "#A08930"),
            primaryLight:       Color(hex: "#22201A"),
            background:         Color(hex: "#0A0A0A"),
            surface:            Color(hex: "#141410"),
            surfaceSecondary:   Color(hex: "#1E1C16"),
            textPrimary:        Color(hex: "#E8DCC8"),
            textSecondary:      Color(hex: "#A08930"),
            textTertiary:       Color(hex: "#706840"),
            separator:          Color(hex: "#22201A"),
            secondary:          Color(hex: "#FFD700"),
            accent:             Color(hex: "#D4AF37"),
            highlight:          Color(hex: "#1E1C16"),
            gradientStart:      Color(hex: "#0A0A0A"),
            gradientEnd:        Color(hex: "#22201A"),
            playerBackground:   Color(hex: "#050505"),
            playerText:         Color(hex: "#E8DCC8"),
            playerSubtext:      Color(hex: "#A08930"),
            progressBackground: Color(hex: "#1E1C16"),
            iconSecondary:      Color(hex: "#706840"),
            tagBackground:      Color(hex: "#22201A"),
            tagText:            Color(hex: "#D4AF37")
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .codeGenerated(.goldDust),
            cardStyle: .minimal,
            fontStyle: .system,
            contentOverlayOpacity: 0.02,
            navigationBarBlur: false,
            tabBarBlur: false
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#D4AF37"),
            end: Color(hex: "#8B7420")
        )
    )
}

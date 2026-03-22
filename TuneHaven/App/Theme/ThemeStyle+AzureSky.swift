import SwiftUI

extension ThemeStyle {
    static let azureSky = ThemeStyle(
        id: "azure_sky",
        displayName: "晴空蔚蓝",
        colorScheme: .light,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#4A9FD8"),
            primaryDark:        Color(hex: "#3A86BE"),
            primaryLight:       Color(hex: "#E3F0FA"),
            background:         Color(hex: "#F5F8FC"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#EDF2F8"),
            textPrimary:        Color(hex: "#1C2D3E"),
            textSecondary:      Color(hex: "#7A8EA0"),
            textTertiary:       Color(hex: "#A0B0C0"),
            separator:          Color(hex: "#DDE6EF"),
            secondary:          Color(hex: "#7FC0E8"),
            accent:             Color(hex: "#E87070"),
            highlight:          Color(hex: "#E3F0FA"),
            gradientStart:      Color(hex: "#4A9FD8"),
            gradientEnd:        Color(hex: "#7FC0E8"),
            playerBackground:   Color(hex: "#EDF2F8"),
            playerText:         Color(hex: "#1C2D3E"),
            playerSubtext:      Color(hex: "#7A8EA0"),
            progressBackground: Color(hex: "#D5DEE8"),
            iconSecondary:      Color(hex: "#A0B0C0"),
            tagBackground:      Color(hex: "#E3F0FA"),
            tagText:            Color(hex: "#3A86BE"),
            elevatedSurface:    Color(hex: "#FFFFFF"),
            cardShadow:         Color.black.opacity(0.06),
            miniPlayerBg:       Color(hex: "#F5F8FC").opacity(0.92),
            hoverHighlight:     Color(hex: "#4A9FD8").opacity(0.07)
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .solidColor,
            cardStyle: .softFloat,
            fontStyle: .system,
            contentOverlayOpacity: 0.0,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#4A9FD8"),
            end: Color(hex: "#7FC0E8")
        )
    )
}

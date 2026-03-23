import SwiftUI

extension ThemeStyle {
    static let cloudWhite = ThemeStyle(
        id: "cloud_white",
        displayName: "素云白简",
        colorScheme: .light,
        palette: ThemeColorPalette(
            primary:            Color(hex: "#4CAF82"),
            primaryDark:        Color(hex: "#3D9B70"),
            primaryLight:       Color(hex: "#E8F5EE"),
            background:         Color(hex: "#F7F6F3"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#F0EFEC"),
            textPrimary:        Color(hex: "#2C2C2E"),
            textSecondary:      Color(hex: "#8E8E93"),
            textTertiary:       Color(hex: "#AEAEB2"),
            separator:          Color(hex: "#E5E5EA"),
            secondary:          Color(hex: "#A8D4B8"),
            accent:             Color(hex: "#E8706A"),
            highlight:          Color(hex: "#E8F5EE"),
            gradientStart:      Color(hex: "#4CAF82"),
            gradientEnd:        Color(hex: "#81C9A3"),
            playerBackground:   Color(hex: "#F0EFEC"),
            playerText:         Color(hex: "#2C2C2E"),
            playerSubtext:      Color(hex: "#8E8E93"),
            progressBackground: Color(hex: "#E0DFD9"),
            iconSecondary:      Color(hex: "#AEAEB2"),
            tagBackground:      Color(hex: "#E8F5EE"),
            tagText:            Color(hex: "#3D9B70"),
            onPrimary:          .white,
            elevatedSurface:    Color(hex: "#FFFFFF"),
            cardShadow:         Color.black.opacity(0.06),
            miniPlayerBg:       Color(hex: "#F7F6F3").opacity(0.92),
            hoverHighlight:     Color(hex: "#4CAF82").opacity(0.08)
        ),
        visualConfig: ThemeVisualConfig(
            backgroundType: .solidColor,
            cardStyle: .softFloat,
            cardConfig: .softFloat,
            fontStyle: .system,
            contentOverlayOpacity: 0.0,
            navigationBarBlur: true,
            tabBarBlur: true
        ),
        previewGradient: GradientPair(
            start: Color(hex: "#4CAF82"),
            end: Color(hex: "#81C9A3")
        )
    )
}

import SwiftUI

// MARK: - 霜色风雅（清冷高级莫兰迪）

extension ThemeStyle {

    static let frostElegance = ThemeStyle(
        id: "frost_elegance",
        displayName: "霜色风雅",
        previewColor: Color(hex: "#8BA5A0"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#8BA5A0"),
            primaryDark:        Color(hex: "#728F89"),
            primaryLight:       Color(hex: "#D0DDD9"),
            background:         Color(hex: "#EFF2F1"),
            surface:            Color(hex: "#FAFBFB"),
            surfaceSecondary:   Color(hex: "#E4EAE8"),
            textPrimary:        Color(hex: "#3D4A4F"),
            textSecondary:      Color(hex: "#6B7D82"),
            textTertiary:       Color(hex: "#95A5AA"),
            separator:          Color(hex: "#D5DEDD"),
            secondary:          Color(hex: "#A3AEB5"),
            accent:             Color(hex: "#9BB0A5"),
            highlight:          Color(hex: "#D0DDD9"),
            gradientStart:      Color(hex: "#8BA5A0"),
            gradientEnd:        Color(hex: "#A3AEB5"),
            playerBackground:   Color(hex: "#1A2422"),
            playerText:         Color(hex: "#E4ECEA"),
            playerSubtext:      Color(hex: "#95A5AA"),
            progressBackground: Color(hex: "#303A38"),
            iconSecondary:      Color(hex: "#95A5AA"),
            tagBackground:      Color(hex: "#E4EAE8"),
            tagText:            Color(hex: "#728F89")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#A0BDB8"),
            primaryDark:        Color(hex: "#8BA5A0"),
            primaryLight:       Color(hex: "#2A3E3A"),
            background:         Color(hex: "#1A2220"),
            surface:            Color(hex: "#252E2C"),
            surfaceSecondary:   Color(hex: "#303A38"),
            textPrimary:        Color(hex: "#E4ECEA"),
            textSecondary:      Color(hex: "#95A5AA"),
            textTertiary:       Color(hex: "#6B7D82"),
            separator:          Color(hex: "#303A38"),
            secondary:          Color(hex: "#B8C3CA"),
            accent:             Color(hex: "#AECAB8"),
            highlight:          Color(hex: "#2A3E3A"),
            gradientStart:      Color(hex: "#A0BDB8"),
            gradientEnd:        Color(hex: "#B8C3CA"),
            playerBackground:   Color(hex: "#0E1614"),
            playerText:         Color(hex: "#E4ECEA"),
            playerSubtext:      Color(hex: "#95A5AA"),
            progressBackground: Color(hex: "#1A2220"),
            iconSecondary:      Color(hex: "#6B7D82"),
            tagBackground:      Color(hex: "#2A3E3A"),
            tagText:            Color(hex: "#A0BDB8")
        )
    )
}

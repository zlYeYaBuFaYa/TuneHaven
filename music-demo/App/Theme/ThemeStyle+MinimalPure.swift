import SwiftUI

// MARK: - 素简之境（现代简约莫兰迪）

extension ThemeStyle {

    static let minimalPure = ThemeStyle(
        id: "minimal_pure",
        displayName: "素简之境",
        previewColor: Color(hex: "#A09890"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#A09890"),
            primaryDark:        Color(hex: "#8A827A"),
            primaryLight:       Color(hex: "#D8D3CC"),
            background:         Color(hex: "#F5F3F0"),
            surface:            Color(hex: "#FAFAF8"),
            surfaceSecondary:   Color(hex: "#EDEAE6"),
            textPrimary:        Color(hex: "#4A4540"),
            textSecondary:      Color(hex: "#7A746E"),
            textTertiary:       Color(hex: "#A09A94"),
            separator:          Color(hex: "#DDD9D4"),
            secondary:          Color(hex: "#B5AEA4"),
            accent:             Color(hex: "#A8A098"),
            highlight:          Color(hex: "#D8D3CC"),
            gradientStart:      Color(hex: "#A09890"),
            gradientEnd:        Color(hex: "#B5AEA4"),
            playerBackground:   Color(hex: "#1E1C1A"),
            playerText:         Color(hex: "#E8E5E2"),
            playerSubtext:      Color(hex: "#A09A94"),
            progressBackground: Color(hex: "#363432"),
            iconSecondary:      Color(hex: "#A09A94"),
            tagBackground:      Color(hex: "#EDEAE6"),
            tagText:            Color(hex: "#8A827A")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#B8B0A8"),
            primaryDark:        Color(hex: "#A09890"),
            primaryLight:       Color(hex: "#3A3632"),
            background:         Color(hex: "#1E1C1A"),
            surface:            Color(hex: "#2A2826"),
            surfaceSecondary:   Color(hex: "#363432"),
            textPrimary:        Color(hex: "#E8E5E2"),
            textSecondary:      Color(hex: "#A09A94"),
            textTertiary:       Color(hex: "#7A746E"),
            separator:          Color(hex: "#363432"),
            secondary:          Color(hex: "#CBC4BA"),
            accent:             Color(hex: "#BEB6AE"),
            highlight:          Color(hex: "#3A3632"),
            gradientStart:      Color(hex: "#B8B0A8"),
            gradientEnd:        Color(hex: "#CBC4BA"),
            playerBackground:   Color(hex: "#12100E"),
            playerText:         Color(hex: "#E8E5E2"),
            playerSubtext:      Color(hex: "#A09A94"),
            progressBackground: Color(hex: "#1E1C1A"),
            iconSecondary:      Color(hex: "#7A746E"),
            tagBackground:      Color(hex: "#3A3632"),
            tagText:            Color(hex: "#B8B0A8")
        )
    )
}

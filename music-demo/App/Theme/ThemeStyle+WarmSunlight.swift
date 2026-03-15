import SwiftUI

// MARK: - 暖阳拾光（温暖莫兰迪）

extension ThemeStyle {

    static let warmSunlight = ThemeStyle(
        id: "warm_sunlight",
        displayName: "暖阳拾光",
        previewColor: Color(hex: "#C4A882"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#C4A882"),
            primaryDark:        Color(hex: "#AD926C"),
            primaryLight:       Color(hex: "#E8D6C2"),
            background:         Color(hex: "#F8F0E8"),
            surface:            Color(hex: "#FDFAF6"),
            surfaceSecondary:   Color(hex: "#F0E6DA"),
            textPrimary:        Color(hex: "#5C4B3C"),
            textSecondary:      Color(hex: "#8A7462"),
            textTertiary:       Color(hex: "#AC9A88"),
            separator:          Color(hex: "#E6D8C8"),
            secondary:          Color(hex: "#D4A28E"),
            accent:             Color(hex: "#C8AD90"),
            highlight:          Color(hex: "#E8D6C2"),
            gradientStart:      Color(hex: "#C4A882"),
            gradientEnd:        Color(hex: "#D4A28E"),
            playerBackground:   Color(hex: "#221C16"),
            playerText:         Color(hex: "#F0E8E0"),
            playerSubtext:      Color(hex: "#AC9A88"),
            progressBackground: Color(hex: "#3E342A"),
            iconSecondary:      Color(hex: "#AC9A88"),
            tagBackground:      Color(hex: "#F0E6DA"),
            tagText:            Color(hex: "#AD926C")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#D8BE98"),
            primaryDark:        Color(hex: "#C4A882"),
            primaryLight:       Color(hex: "#4A3A28"),
            background:         Color(hex: "#221C16"),
            surface:            Color(hex: "#302820"),
            surfaceSecondary:   Color(hex: "#3E342A"),
            textPrimary:        Color(hex: "#F0E8E0"),
            textSecondary:      Color(hex: "#AC9A88"),
            textTertiary:       Color(hex: "#8A7462"),
            separator:          Color(hex: "#3E342A"),
            secondary:          Color(hex: "#E4B8A2"),
            accent:             Color(hex: "#D8C0A8"),
            highlight:          Color(hex: "#4A3A28"),
            gradientStart:      Color(hex: "#D8BE98"),
            gradientEnd:        Color(hex: "#E4B8A2"),
            playerBackground:   Color(hex: "#160F0A"),
            playerText:         Color(hex: "#F0E8E0"),
            playerSubtext:      Color(hex: "#AC9A88"),
            progressBackground: Color(hex: "#221C16"),
            iconSecondary:      Color(hex: "#8A7462"),
            tagBackground:      Color(hex: "#4A3A28"),
            tagText:            Color(hex: "#D8BE98")
        )
    )
}

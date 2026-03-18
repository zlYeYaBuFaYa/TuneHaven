import SwiftUI

// MARK: - 玫瑰梦境（少女粉莫兰迪）

extension ThemeStyle {

    static let roseDream = ThemeStyle(
        id: "rose_dream",
        displayName: "玫瑰梦境",
        previewColor: Color(hex: "#D4A5A5"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#D4A5A5"),
            primaryDark:        Color(hex: "#C08E8E"),
            primaryLight:       Color(hex: "#F2D0C7"),
            background:         Color(hex: "#FDF0ED"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#F9E4DF"),
            textPrimary:        Color(hex: "#6B4F5F"),
            textSecondary:      Color(hex: "#9A7E8A"),
            textTertiary:       Color(hex: "#BFA3AF"),
            separator:          Color(hex: "#EEDAD5"),
            secondary:          Color(hex: "#C9B1BD"),
            accent:             Color(hex: "#E2BAA8"),
            highlight:          Color(hex: "#F2D0C7"),
            gradientStart:      Color(hex: "#D4A5A5"),
            gradientEnd:        Color(hex: "#C9B1BD"),
            playerBackground:   Color(hex: "#2A1C22"),
            playerText:         Color(hex: "#F0E4E8"),
            playerSubtext:      Color(hex: "#BFA3AF"),
            progressBackground: Color(hex: "#4A3840"),
            iconSecondary:      Color(hex: "#BFA3AF"),
            tagBackground:      Color(hex: "#F9E4DF"),
            tagText:            Color(hex: "#C08E8E")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#E0B5B5"),
            primaryDark:        Color(hex: "#D4A5A5"),
            primaryLight:       Color(hex: "#5A3040"),
            background:         Color(hex: "#2A1C22"),
            surface:            Color(hex: "#382830"),
            surfaceSecondary:   Color(hex: "#4A3840"),
            textPrimary:        Color(hex: "#F0E4E8"),
            textSecondary:      Color(hex: "#BFA3AF"),
            textTertiary:       Color(hex: "#9A7E8A"),
            separator:          Color(hex: "#4A3840"),
            secondary:          Color(hex: "#D5C1CC"),
            accent:             Color(hex: "#EECCA0"),
            highlight:          Color(hex: "#4A3040"),
            gradientStart:      Color(hex: "#E0B5B5"),
            gradientEnd:        Color(hex: "#D5C1CC"),
            playerBackground:   Color(hex: "#1A0E14"),
            playerText:         Color(hex: "#F0E4E8"),
            playerSubtext:      Color(hex: "#BFA3AF"),
            progressBackground: Color(hex: "#2A1C22"),
            iconSecondary:      Color(hex: "#9A7E8A"),
            tagBackground:      Color(hex: "#5A3040"),
            tagText:            Color(hex: "#E0B5B5")
        )
    )
}

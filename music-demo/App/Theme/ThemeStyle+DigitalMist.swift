import SwiftUI

// MARK: - 数字迷雾（科技莫兰迪）

extension ThemeStyle {

    static let digitalMist = ThemeStyle(
        id: "digital_mist",
        displayName: "数字迷雾",
        previewColor: Color(hex: "#7E8FA5"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#6A7B91"),
            primaryDark:        Color(hex: "#566880"),
            primaryLight:       Color(hex: "#D0D8E2"),
            background:         Color(hex: "#F0F2F5"),
            surface:            Color(hex: "#FAFBFC"),
            surfaceSecondary:   Color(hex: "#E8EBF0"),
            textPrimary:        Color(hex: "#2A3040"),
            textSecondary:      Color(hex: "#6B7280"),
            textTertiary:       Color(hex: "#9AA0AC"),
            separator:          Color(hex: "#D8DCE2"),
            secondary:          Color(hex: "#5A6A7A"),
            accent:             Color(hex: "#7888A0"),
            highlight:          Color(hex: "#D0D8E2"),
            gradientStart:      Color(hex: "#6A7B91"),
            gradientEnd:        Color(hex: "#5A6A7A"),
            playerBackground:   Color(hex: "#1E2128"),
            playerText:         Color(hex: "#D0D4DA"),
            playerSubtext:      Color(hex: "#9AA0AC"),
            progressBackground: Color(hex: "#3A4050"),
            iconSecondary:      Color(hex: "#9AA0AC"),
            tagBackground:      Color(hex: "#E8EBF0"),
            tagText:            Color(hex: "#566880")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#7E8FA5"),
            primaryDark:        Color(hex: "#6A7B91"),
            primaryLight:       Color(hex: "#353B48"),
            background:         Color(hex: "#1E2128"),
            surface:            Color(hex: "#2C313A"),
            surfaceSecondary:   Color(hex: "#343A44"),
            textPrimary:        Color(hex: "#D0D4DA"),
            textSecondary:      Color(hex: "#9AA0AC"),
            textTertiary:       Color(hex: "#6B7280"),
            separator:          Color(hex: "#3A4050"),
            secondary:          Color(hex: "#6B7A8A"),
            accent:             Color(hex: "#8A97A8"),
            highlight:          Color(hex: "#353B48"),
            gradientStart:      Color(hex: "#7E8FA5"),
            gradientEnd:        Color(hex: "#6B7A8A"),
            playerBackground:   Color(hex: "#14171C"),
            playerText:         Color(hex: "#D0D4DA"),
            playerSubtext:      Color(hex: "#9AA0AC"),
            progressBackground: Color(hex: "#1E2128"),
            iconSecondary:      Color(hex: "#6B7280"),
            tagBackground:      Color(hex: "#353B48"),
            tagText:            Color(hex: "#7E8FA5")
        )
    )
}

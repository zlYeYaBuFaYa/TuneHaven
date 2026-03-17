import SwiftUI

// MARK: - 赤焰科技（硬核科技风）

extension ThemeStyle {

    static let crimsonTech = ThemeStyle(
        id: "crimson_tech",
        displayName: "赤焰科技",
        previewColor: Color(hex: "#D32F2F"),
        lightPalette: ThemeColorPalette(
            primary:            Color(hex: "#D32F2F"),
            primaryDark:        Color(hex: "#B71C1C"),
            primaryLight:       Color(hex: "#FFCDD2"),
            background:         Color(hex: "#FAFAFA"),
            surface:            Color(hex: "#FFFFFF"),
            surfaceSecondary:   Color(hex: "#F5F5F5"),
            textPrimary:        Color(hex: "#212121"),
            textSecondary:      Color(hex: "#757575"),
            textTertiary:       Color(hex: "#BDBDBD"),
            separator:          Color(hex: "#E0E0E0"),
            secondary:          Color(hex: "#FF5252"),
            accent:             Color(hex: "#FF1744"),
            highlight:          Color(hex: "#FFEBEE"),
            gradientStart:      Color(hex: "#D32F2F"),
            gradientEnd:        Color(hex: "#FF5252"),
            playerBackground:   Color(hex: "#1A0A0A"),
            playerText:         Color(hex: "#FAFAFA"),
            playerSubtext:      Color(hex: "#BDBDBD"),
            progressBackground: Color(hex: "#3D1515"),
            iconSecondary:      Color(hex: "#BDBDBD"),
            tagBackground:      Color(hex: "#FFEBEE"),
            tagText:            Color(hex: "#B71C1C")
        ),
        darkPalette: ThemeColorPalette(
            primary:            Color(hex: "#FF5252"),
            primaryDark:        Color(hex: "#D32F2F"),
            primaryLight:       Color(hex: "#4A2020"),
            background:         Color(hex: "#161616"),
            surface:            Color(hex: "#242424"),
            surfaceSecondary:   Color(hex: "#2E2E2E"),
            textPrimary:        Color(hex: "#F5F5F5"),
            textSecondary:      Color(hex: "#BDBDBD"),
            textTertiary:       Color(hex: "#757575"),
            separator:          Color(hex: "#333333"),
            secondary:          Color(hex: "#FF8A80"),
            accent:             Color(hex: "#FF5252"),
            highlight:          Color(hex: "#3D1818"),
            gradientStart:      Color(hex: "#FF5252"),
            gradientEnd:        Color(hex: "#FF8A80"),
            playerBackground:   Color(hex: "#0D0D0D"),
            playerText:         Color(hex: "#F5F5F5"),
            playerSubtext:      Color(hex: "#BDBDBD"),
            progressBackground: Color(hex: "#1A1A1A"),
            iconSecondary:      Color(hex: "#757575"),
            tagBackground:      Color(hex: "#3D1818"),
            tagText:            Color(hex: "#FF5252")
        )
    )
}

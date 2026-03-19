import SwiftUI

// MARK: - 渐变色对

struct GradientPair: Equatable {
    let start: Color
    let end: Color
}

// MARK: - 主题风格定义

struct ThemeStyle: Identifiable, Equatable {
    let id: String
    let displayName: String
    let colorScheme: ColorScheme
    let palette: ThemeColorPalette
    let visualConfig: ThemeVisualConfig
    let previewGradient: GradientPair

    static func == (lhs: ThemeStyle, rhs: ThemeStyle) -> Bool {
        lhs.id == rhs.id
    }
}

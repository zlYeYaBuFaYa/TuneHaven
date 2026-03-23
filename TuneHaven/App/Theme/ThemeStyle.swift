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

    /// 按 identity（id）判等：同一 id 视为同一主题。palette/visualConfig 在运行时不会被修改，
    /// ThemeStyle 为值类型且仅通过 ThemeRegistry 分发，保证同 id 实例内容一致。
    static func == (lhs: ThemeStyle, rhs: ThemeStyle) -> Bool {
        lhs.id == rhs.id
    }
}

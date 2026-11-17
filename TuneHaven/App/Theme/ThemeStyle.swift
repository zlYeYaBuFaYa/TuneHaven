import SwiftUI

// MARK: - 渐变色对

struct GradientPair: Equatable {
    let start: Color
    let end: Color
}

// MARK: - 主题风格定义

/// 一个主题 = 一个色系（云霞／晴屿／月晕）。深浅外观跟随系统，色板中的颜色都是动态色。
struct ThemeStyle: Identifiable, Equatable {
    let id: String
    let displayName: String
    let day: ThemeTokens
    let night: ThemeTokens
    let palette: ThemeColorPalette
    let visualConfig: ThemeVisualConfig
    let previewGradient: GradientPair

    init(id: String, displayName: String, day: ThemeTokens, night: ThemeTokens) {
        self.id = id
        self.displayName = displayName
        self.day = day
        self.night = night
        let palette = ThemeColorPalette.make(day: day, night: night)
        self.palette = palette
        self.visualConfig = .softGlow
        self.previewGradient = GradientPair(start: palette.glowA, end: palette.glowB)
    }

    /// 按 identity（id）判等：同一 id 视为同一主题。
    static func == (lhs: ThemeStyle, rhs: ThemeStyle) -> Bool {
        lhs.id == rhs.id
    }
}

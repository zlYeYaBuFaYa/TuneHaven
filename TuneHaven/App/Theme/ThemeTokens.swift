import SwiftUI
import UIKit

/// 设计文档（docs/UI设计文档.md §4）定义的一套外观的语义令牌。每个主题提供日间、黑夜两套。
/// 业务组件不直接使用这里的色号，而是通过由它派生的 `ThemeColorPalette`。
struct ThemeTokens: Equatable, Sendable {
    let background: UInt32
    /// 左侧、右侧、下部三束背景光晕
    let glowA: UInt32
    let glowB: UInt32
    let glowC: UInt32
    let textPrimary: UInt32
    let textSecondary: UInt32
    /// 主操作底色（播放、选中分段）
    let actionFill: UInt32
    /// 主操作上的图标与文字
    let onAction: UInt32
    /// 播放指示、歌词重点
    let accent: UInt32
    /// 材质回退、弹层内容底
    let surfaceOpaque: UInt32
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// 跟随系统深浅外观切换的颜色
    static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        dynamic(light: UIColor(rgb: light, alpha: alpha), dark: UIColor(rgb: dark, alpha: alpha))
    }

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension ThemeColorPalette {
    /// 由日间、黑夜两套令牌派生完整色板。所有颜色都随系统深浅外观切换。
    static func make(day: ThemeTokens, night: ThemeTokens) -> ThemeColorPalette {
        func pick(_ key: KeyPath<ThemeTokens, UInt32>, alpha: CGFloat = 1) -> Color {
            .dynamic(light: day[keyPath: key], dark: night[keyPath: key], alpha: alpha)
        }
        let accent = pick(\.accent)
        let textPrimary = pick(\.textPrimary)
        let textSecondary = pick(\.textSecondary)
        let surface = pick(\.surfaceOpaque)
        return ThemeColorPalette(
            primary: accent,
            primaryDark: pick(\.actionFill),
            primaryLight: pick(\.accent, alpha: 0.14),
            background: pick(\.background),
            surface: surface,
            surfaceSecondary: pick(\.textPrimary, alpha: 0.05),
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            // 第三级文字也要满足 4.5:1，直接沿用次文字色
            textTertiary: textSecondary,
            separator: pick(\.textPrimary, alpha: 0.1),
            secondary: pick(\.glowB),
            accent: accent,
            highlight: pick(\.accent, alpha: 0.12),
            gradientStart: pick(\.glowA),
            gradientEnd: pick(\.glowB),
            playerBackground: pick(\.background),
            playerText: textPrimary,
            playerSubtext: textSecondary,
            progressBackground: pick(\.textPrimary, alpha: 0.14),
            iconSecondary: textSecondary,
            tagBackground: pick(\.accent, alpha: 0.14),
            tagText: accent,
            // 重点色日间偏深、黑夜偏浅，与主操作同向，前景色可共用 onAction
            onPrimary: pick(\.onAction),
            elevatedSurface: surface,
            cardShadow: .dynamic(light: UIColor.black.withAlphaComponent(0.06), dark: UIColor.black.withAlphaComponent(0.3)),
            miniPlayerBg: pick(\.surfaceOpaque, alpha: 0.92),
            hoverHighlight: pick(\.accent, alpha: 0.08),
            glowA: pick(\.glowA),
            glowB: pick(\.glowB),
            glowC: pick(\.glowC),
            actionFill: pick(\.actionFill),
            onAction: pick(\.onAction)
        )
    }
}

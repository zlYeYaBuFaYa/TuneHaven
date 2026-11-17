import SwiftUI

/// 三套主题，色值来自 docs/UI设计文档.md §4。深浅外观跟随系统，三套都免费。
extension ThemeStyle {
    /// A 云霞：日间粉蓝柔光，黑夜玫瑰雾、烟蓝与低亮度紫
    static let cloudHaze = ThemeStyle(
        id: "cloud_haze",
        displayName: "云霞",
        day: ThemeTokens(
            background: 0xF9F7FB, glowA: 0xF1CCE3, glowB: 0xC9E4F6, glowC: 0xDDD5F5,
            textPrimary: 0x1B1B22, textSecondary: 0x5B5968,
            actionFill: 0x222128, onAction: 0xFFFFFF, accent: 0x5E4E88, surfaceOpaque: 0xFFFFFF
        ),
        night: ThemeTokens(
            background: 0x16141E, glowA: 0x512D48, glowB: 0x263A54, glowC: 0x3C3055,
            textPrimary: 0xEEE9F1, textSecondary: 0xB6ADBF,
            actionFill: 0xE4C5DB, onAction: 0x302336, accent: 0xE7C4DE, surfaceOpaque: 0x282330
        )
    )

    /// B 晴屿：日间薄荷与暖杏，黑夜墨绿与琥珀
    static let clearIsle = ThemeStyle(
        id: "clear_isle",
        displayName: "晴屿",
        day: ThemeTokens(
            background: 0xF6FAF7, glowA: 0xBDE5D8, glowB: 0xFFE1BD, glowC: 0xDBEDDC,
            textPrimary: 0x1B1B22, textSecondary: 0x4D6059,
            actionFill: 0x243C34, onAction: 0xFFFFFF, accent: 0x316352, surfaceOpaque: 0xFFFFFF
        ),
        night: ThemeTokens(
            background: 0x121C18, glowA: 0x1B493C, glowB: 0x51422C, glowC: 0x233D33,
            textPrimary: 0xEAF0E9, textSecondary: 0xB0C3B7,
            actionFill: 0xC0DDC9, onAction: 0x20392C, accent: 0xC0DDC9, surfaceOpaque: 0x24352D
        )
    )

    /// C 月晕：日间冰蓝与淡紫，黑夜午夜蓝与烟紫
    static let moonHalo = ThemeStyle(
        id: "moon_halo",
        displayName: "月晕",
        day: ThemeTokens(
            background: 0xF6F7FC, glowA: 0xC9DDF8, glowB: 0xDDD0FA, glowC: 0xD9E7FA,
            textPrimary: 0x1B1B22, textSecondary: 0x535971,
            actionFill: 0x2D344B, onAction: 0xFFFFFF, accent: 0x505B92, surfaceOpaque: 0xFFFFFF
        ),
        night: ThemeTokens(
            background: 0x141B2C, glowA: 0x203E68, glowB: 0x3E315F, glowC: 0x293C61,
            textPrimary: 0xE8EDF7, textSecondary: 0xB1BDD5,
            actionFill: 0xC6D0EE, onAction: 0x242E48, accent: 0xC4CFF2, surfaceOpaque: 0x232C43
        )
    )
}

import Testing
import SwiftUI
@testable import TuneHaven

@Suite("主题对比度")
struct PaletteContrastTests {

    private struct Sample {
        let name: String
        let style: ThemeStyle
        let scheme: ColorScheme
    }

    private let samples = [
        Sample(name: "素云白简", style: .cloudWhite, scheme: .light),
        Sample(name: "晴空蔚蓝", style: .azureSky, scheme: .light),
        Sample(name: "暮光玫瑰", style: .twilightRose, scheme: .dark),
        Sample(name: "星际穹顶", style: .cosmicTech, scheme: .dark),
    ]

    @Test("文字、主色、按钮字和语义红在浅色与深色主题上达到 4.5:1")
    func foregroundsMeetBodyContrast() {
        for sample in samples {
            let palette = sample.style.palette
            let floors = [
                "background": palette.background,
                "surface": palette.surface,
                "elevatedSurface": palette.elevatedSurface,
                "playerBackground": palette.playerBackground,
            ]
            for (floorName, floor) in floors {
                expectAtLeastBody("\(sample.name) textPrimary/\(floorName)", palette.textPrimary, floor)
                expectAtLeastBody("\(sample.name) textSecondary/\(floorName)", palette.textSecondary, floor)
                expectAtLeastBody("\(sample.name) textTertiary/\(floorName)", palette.textTertiary, floor)
                expectAtLeastBody("\(sample.name) primary/\(floorName)", palette.primary, floor)
                expectAtLeastBody("\(sample.name) iconSecondary/\(floorName)", palette.iconSecondary, floor)
            }
            expectAtLeastBody("\(sample.name) onPrimary/primary", palette.onPrimary, palette.primary)
            expectAtLeastBody("\(sample.name) onPrimary/textTertiary", palette.onPrimary, palette.textTertiary)
            expectAtLeastBody("\(sample.name) playerText/playerBackground", palette.playerText, palette.playerBackground)
            expectAtLeastBody("\(sample.name) playerSubtext/playerBackground", palette.playerSubtext, palette.playerBackground)
            expectAtLeastBody("\(sample.name) tagText/tagBackground", palette.tagText, palette.tagBackground)

            let danger = SemanticColor.danger(for: sample.scheme)
            expectAtLeastBody("\(sample.name) danger/background", danger, palette.background)
            expectAtLeastBody("\(sample.name) danger/surface", danger, palette.surface)

            let secondary = contrast(palette.textSecondary, palette.background)
            let tertiary = contrast(palette.textTertiary, palette.background)
            #expect(secondary > tertiary, "\(sample.name) 的次级文字应比三级文字更易读")
        }
    }

    @Test("静态 danger 浅色保持 4.5:1，暗色不低于改前 #EF4444")
    func staticDangerFollowsColorScheme() {
        let lightRed = Color(hex: "#C62828")
        let legacyDark = Color(hex: "#EF4444")
        for sample in samples {
            let danger = resolved(SemanticColor.danger, scheme: sample.scheme)
            let expected = sample.scheme == .dark ? legacyDark : lightRed
            expectSameRed("\(sample.name) 静态 danger", danger, expected)

            let palette = sample.style.palette
            let floors = [
                "background": palette.background,
                "surface": palette.surface,
                "elevatedSurface": palette.elevatedSurface,
                "playerBackground": palette.playerBackground,
            ]
            for (floorName, floor) in floors {
                let ratio = contrast(danger, floor)
                let label = "\(sample.name) static danger/\(floorName)"
                if sample.scheme == .light {
                    #expect(ratio >= 4.5, "\(label) 对比度 \(ratio) 低于 4.5")
                } else {
                    let legacyRatio = contrast(legacyDark, floor)
                    // 0.02 只吸收动态色解析的量化误差。#C62828 在暗色底上大约低 1.5，过不了这道线。
                    #expect(
                        ratio + 0.02 >= legacyRatio,
                        "\(label) 对比度 \(ratio) 低于改前 #EF4444 的 \(legacyRatio)"
                    )
                }
            }
        }
    }

    private func expectAtLeastBody(_ label: String, _ foreground: Color, _ background: Color) {
        let ratio = contrast(foreground, background)
        #expect(ratio >= 4.5, "\(label) 对比度 \(ratio) 低于 4.5")
    }

    private func contrast(_ foreground: Color, _ background: Color) -> Double {
        let left = luminance(foreground)
        let right = luminance(background)
        let lighter = max(left, right)
        let darker = min(left, right)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        func channel(_ value: Float) -> Double {
            let srgb = Double(value)
            if srgb <= 0.04045 {
                return srgb / 12.92
            }
            return pow((srgb + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(resolved.red)
            + 0.7152 * channel(resolved.green)
            + 0.0722 * channel(resolved.blue)
    }

    /// 按界面深浅解析颜色，再烘焙成普通 sRGB，避免后续对比度计算又落回浅色。
    private func resolved(_ color: Color, scheme: ColorScheme) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let value = color.resolve(in: environment)
        return Color(
            .sRGB,
            red: Double(value.red),
            green: Double(value.green),
            blue: Double(value.blue),
            opacity: Double(value.opacity)
        )
    }

    private func expectSameRed(_ label: String, _ actual: Color, _ expected: Color) {
        let left = actual.resolve(in: EnvironmentValues())
        let right = expected.resolve(in: EnvironmentValues())
        let tolerance: Float = 0.02
        #expect(abs(left.red - right.red) < tolerance, "\(label) 红色通道偏离")
        #expect(abs(left.green - right.green) < tolerance, "\(label) 绿色通道偏离")
        #expect(abs(left.blue - right.blue) < tolerance, "\(label) 蓝色通道偏离")
    }
}

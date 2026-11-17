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

    private let samples: [Sample] = [ThemeStyle.cloudHaze, .clearIsle, .moonHalo].flatMap { style in
        [
            Sample(name: "\(style.displayName)日间", style: style, scheme: .light),
            Sample(name: "\(style.displayName)黑夜", style: style, scheme: .dark),
        ]
    }

    @Test("文字、主色、主操作前景和语义红在六套外观上达到 4.5:1")
    func foregroundsMeetBodyContrast() {
        for sample in samples {
            let p = sample.style.palette
            let on = { (color: Color) in self.resolved(color, scheme: sample.scheme) }
            let background = on(p.background)
            let floors = [
                "background": background,
                "surface": on(p.surface),
                "elevatedSurface": on(p.elevatedSurface),
                "playerBackground": on(p.playerBackground),
            ]
            for (floorName, floor) in floors {
                expectAtLeastBody("\(sample.name) textPrimary/\(floorName)", on(p.textPrimary), floor)
                expectAtLeastBody("\(sample.name) textSecondary/\(floorName)", on(p.textSecondary), floor)
                expectAtLeastBody("\(sample.name) textTertiary/\(floorName)", on(p.textTertiary), floor)
                expectAtLeastBody("\(sample.name) primary/\(floorName)", on(p.primary), floor)
                expectAtLeastBody("\(sample.name) iconSecondary/\(floorName)", on(p.iconSecondary), floor)
            }
            expectAtLeastBody("\(sample.name) onPrimary/primary", on(p.onPrimary), on(p.primary))
            expectAtLeastBody("\(sample.name) onAction/actionFill", on(p.onAction), on(p.actionFill))
            expectAtLeastBody("\(sample.name) playerText/playerBackground", on(p.playerText), on(p.playerBackground))
            expectAtLeastBody("\(sample.name) playerSubtext/playerBackground", on(p.playerSubtext), on(p.playerBackground))
            // 半透明底色先叠到页面底色上再计算
            let tagFloor = composite(on(p.tagBackground), over: background)
            expectAtLeastBody("\(sample.name) tagText/tagBackground", on(p.tagText), tagFloor)
            let highlightFloor = composite(on(p.highlight), over: background)
            expectAtLeastBody("\(sample.name) textPrimary/highlight", on(p.textPrimary), highlightFloor)

            let danger = SemanticColor.danger(for: sample.scheme)
            expectAtLeastBody("\(sample.name) danger/background", danger, background)
            expectAtLeastBody("\(sample.name) danger/surface", danger, on(p.surface))
        }
    }

    @Test("主文字叠在光晕最亮处仍达到 4.5:1")
    func textOverGlowMeetsContrast() {
        for sample in samples {
            let p = sample.style.palette
            for (name, glow) in [("glowA", p.glowA), ("glowB", p.glowB), ("glowC", p.glowC)] {
                let floor = resolved(glow, scheme: sample.scheme)
                expectAtLeastBody("\(sample.name) textPrimary/\(name)", resolved(p.textPrimary, scheme: sample.scheme), floor)
                expectAtLeastBody("\(sample.name) textSecondary/\(name)", resolved(p.textSecondary, scheme: sample.scheme), floor)
            }
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

            let p = sample.style.palette
            let floors = [
                "background": resolved(p.background, scheme: sample.scheme),
                "surface": resolved(p.surface, scheme: sample.scheme),
            ]
            for (floorName, floor) in floors {
                let ratio = contrast(danger, floor)
                let label = "\(sample.name) static danger/\(floorName)"
                if sample.scheme == .light {
                    #expect(ratio >= 4.5, "\(label) 对比度 \(ratio) 低于 4.5")
                } else {
                    let legacyRatio = contrast(legacyDark, floor)
                    #expect(
                        ratio + 0.02 >= legacyRatio,
                        "\(label) 对比度 \(ratio) 低于改前 #EF4444 的 \(legacyRatio)"
                    )
                }
            }
        }
    }

    /// 把带透明度的前景按 alpha 叠到不透明底色上
    private func composite(_ top: Color, over base: Color) -> Color {
        let t = top.resolve(in: EnvironmentValues())
        let b = base.resolve(in: EnvironmentValues())
        let a = Double(t.opacity)
        func mix(_ x: Float, _ y: Float) -> Double { Double(x) * a + Double(y) * (1 - a) }
        return Color(.sRGB, red: mix(t.red, b.red), green: mix(t.green, b.green), blue: mix(t.blue, b.blue), opacity: 1)
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

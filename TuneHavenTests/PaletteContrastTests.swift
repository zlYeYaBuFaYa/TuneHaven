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
}

import Testing
import Foundation
import SwiftUI
@testable import TuneHaven

// MARK: - ThemeRegistry Tests

@Suite("ThemeRegistry Tests")
struct ThemeRegistryTests {

    init() {
        ThemeRegistry.shared.reset()
        ThemeRegistry.shared.bootstrap()
    }

    @Test("bootstrap 后注册表包含 4 个主题")
    func testAllThemesCount() {
        #expect(ThemeRegistry.shared.allThemes.count == 4)
    }

    @Test("所有主题 id 唯一")
    func testAllThemeIdsUnique() {
        let ids = ThemeRegistry.shared.allThemes.map { $0.id }
        #expect(ids.count == Set(ids).count)
    }

    @Test("所有主题 displayName 不为空")
    func testAllThemeDisplayNamesNotEmpty() {
        for theme in ThemeRegistry.shared.allThemes {
            #expect(!theme.displayName.isEmpty, "主题 \(theme.id) 的 displayName 不应为空")
        }
    }

    @Test("可通过 id 查找新主题")
    func testThemeLookup() {
        #expect(ThemeRegistry.shared.theme(for: "cloud_white") != nil)
        #expect(ThemeRegistry.shared.theme(for: "azure_sky") != nil)
        #expect(ThemeRegistry.shared.theme(for: "twilight_rose") != nil)
        #expect(ThemeRegistry.shared.theme(for: "cosmic_tech") != nil)
    }

    @Test("查找不存在的 id 返回 nil")
    func testThemeLookupNotFound() {
        #expect(ThemeRegistry.shared.theme(for: "nonexistent") == nil)
    }

    @Test("旧主题 id 查找返回 nil（已移除）")
    func testOldThemeIdsReturnNil() {
        #expect(ThemeRegistry.shared.theme(for: "mint_breeze") == nil)
        #expect(ThemeRegistry.shared.theme(for: "deep_ocean") == nil)
        #expect(ThemeRegistry.shared.theme(for: "cyber_neon") == nil)
        #expect(ThemeRegistry.shared.theme(for: "glacier_blue") == nil)
        #expect(ThemeRegistry.shared.theme(for: "aurora_dream") == nil)
        #expect(ThemeRegistry.shared.theme(for: "midnight_gold") == nil)
    }

    @Test("默认主题为素云白简")
    func testDefaultTheme() {
        #expect(ThemeRegistry.shared.defaultTheme.id == "cloud_white")
    }

    @Test("Light 主题的 colorScheme 为 .light")
    func testLightThemesHaveLightScheme() {
        for id in ["cloud_white", "azure_sky"] {
            let theme = ThemeRegistry.shared.theme(for: id)
            #expect(theme?.colorScheme == .light, "\(id) should be .light")
        }
    }

    @Test("Dark 主题的 colorScheme 为 .dark")
    func testDarkThemesHaveDarkScheme() {
        for id in ["twilight_rose", "cosmic_tech"] {
            let theme = ThemeRegistry.shared.theme(for: id)
            #expect(theme?.colorScheme == .dark, "\(id) should be .dark")
        }
    }

    @Test("重复 register 不会导致重复主题")
    func testDuplicateRegisterIgnored() {
        let before = ThemeRegistry.shared.allThemes.count
        ThemeRegistry.shared.register(.cloudWhite)
        #expect(ThemeRegistry.shared.allThemes.count == before)
    }

    @Test("reset 后注册表为空")
    func testResetClearsAll() {
        ThemeRegistry.shared.reset()
        #expect(ThemeRegistry.shared.allThemes.isEmpty)
        ThemeRegistry.shared.bootstrap()
    }
}

// MARK: - ThemeStyle Tests

@Suite("ThemeStyle Tests")
struct ThemeStyleTests {

    @Test("cloudWhite 的 id 正确")
    func testCloudWhiteId() {
        #expect(ThemeStyle.cloudWhite.id == "cloud_white")
    }

    @Test("azureSky 的 id 正确")
    func testAzureSkyId() {
        #expect(ThemeStyle.azureSky.id == "azure_sky")
    }

    @Test("twilightRose 的 id 正确")
    func testTwilightRoseId() {
        #expect(ThemeStyle.twilightRose.id == "twilight_rose")
    }

    @Test("cosmicTech 的 id 正确")
    func testCosmicTechId() {
        #expect(ThemeStyle.cosmicTech.id == "cosmic_tech")
    }

    @Test("所有主题的 Identifiable id 不为空")
    func testIdentifiable() {
        let themes: [ThemeStyle] = [
            .cloudWhite, .azureSky, .twilightRose, .cosmicTech
        ]
        for style in themes {
            #expect(!style.id.isEmpty)
        }
    }

    @Test("ThemeStyle Equatable 基于 id 判等")
    func testEquatable() {
        #expect(ThemeStyle.cloudWhite == ThemeStyle.cloudWhite)
        #expect(ThemeStyle.cloudWhite != ThemeStyle.cosmicTech)
    }

    @Test("cosmicTech 有专属 cosmicParticles 背景")
    func testCosmicTechHasCustomBackground() {
        #expect(ThemeStyle.cosmicTech.hasCustomBackground == true)
        #expect(ThemeStyle.cosmicTech.visualConfig.backgroundType == .codeGenerated(.cosmicParticles))
    }

    @Test("cloudWhite 使用 solidColor 背景")
    func testCloudWhiteSolidBackground() {
        #expect(ThemeStyle.cloudWhite.hasCustomBackground == false)
        #expect(ThemeStyle.cloudWhite.visualConfig.backgroundType == .solidColor)
    }
}

// MARK: - ThemeColorPalette Tests

@Suite("ThemeColorPalette Tests")
struct ThemeColorPaletteTests {

    @Test("cloudWhite palette 所有颜色字段可被访问（含新增 4 个）")
    func testCloudWhitePaletteAccessible() {
        let palette = ThemeStyle.cloudWhite.palette
        _ = palette.primary
        _ = palette.primaryDark
        _ = palette.primaryLight
        _ = palette.background
        _ = palette.surface
        _ = palette.surfaceSecondary
        _ = palette.textPrimary
        _ = palette.textSecondary
        _ = palette.textTertiary
        _ = palette.separator
        _ = palette.secondary
        _ = palette.accent
        _ = palette.highlight
        _ = palette.gradientStart
        _ = palette.gradientEnd
        _ = palette.playerBackground
        _ = palette.playerText
        _ = palette.playerSubtext
        _ = palette.progressBackground
        _ = palette.iconSecondary
        _ = palette.tagBackground
        _ = palette.tagText
        _ = palette.elevatedSurface
        _ = palette.cardShadow
        _ = palette.miniPlayerBg
        _ = palette.hoverHighlight
    }

    @Test("每个主题都有完整的 palette（26 属性）")
    func testEachStyleHasPalette() {
        let themes: [ThemeStyle] = [
            .cloudWhite, .azureSky, .twilightRose, .cosmicTech
        ]
        for style in themes {
            _ = style.palette.primary
            _ = style.palette.background
            _ = style.palette.textPrimary
            _ = style.palette.gradientStart
            _ = style.palette.elevatedSurface
            _ = style.palette.cardShadow
            _ = style.palette.miniPlayerBg
            _ = style.palette.hoverHighlight
        }
    }
}

// MARK: - Color+Hex Tests

@Suite("Color+Hex Tests")
struct ColorHexTests {

    @Test("6 位 HEX 带 # 号可正常初始化")
    func testHex6DigitWithHash() {
        _ = Color(hex: "#10B981")
        _ = Color(hex: "#FFFFFF")
        _ = Color(hex: "#000000")
    }

    @Test("6 位 HEX 不带 # 号可正常初始化")
    func testHex6DigitWithoutHash() {
        _ = Color(hex: "10B981")
        _ = Color(hex: "FF0000")
    }

    @Test("3 位 HEX 可正常初始化（扩展为 6 位）")
    func testHex3Digit() {
        _ = Color(hex: "#FFF")
        _ = Color(hex: "#000")
        _ = Color(hex: "#F00")
    }

    @Test("8 位 HEX（含 alpha 通道）可正常初始化")
    func testHex8Digit() {
        _ = Color(hex: "#FF10B981")
        _ = Color(hex: "#80FFFFFF")
    }

    @Test("小写 HEX 可正常初始化")
    func testHexLowercase() {
        _ = Color(hex: "#10b981")
        _ = Color(hex: "ff0000")
    }
}

// MARK: - SemanticColor Tests

@Suite("SemanticColor Tests")
struct SemanticColorTests {

    @Test("所有语义色可正常初始化")
    func testAllSemanticColors() {
        _ = SemanticColor.danger
        _ = SemanticColor.warning
        _ = SemanticColor.success
        _ = SemanticColor.info
        _ = SemanticColor.dangerDark
        _ = SemanticColor.warningDark
        _ = SemanticColor.successDark
    }
}

// MARK: - GradientPair Tests

@Suite("GradientPair Tests")
struct GradientPairTests {

    @Test("GradientPair Equatable")
    func testEquatable() {
        let a = GradientPair(start: Color(hex: "#FF0000"), end: Color(hex: "#00FF00"))
        let b = GradientPair(start: Color(hex: "#FF0000"), end: Color(hex: "#00FF00"))
        #expect(a == b)
    }
}

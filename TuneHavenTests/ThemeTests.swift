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

    @Test("bootstrap 后注册表包含 6 个主题")
    func testAllThemesCount() {
        #expect(ThemeRegistry.shared.allThemes.count == 6)
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
        #expect(ThemeRegistry.shared.theme(for: "mint_breeze") != nil)
        #expect(ThemeRegistry.shared.theme(for: "deep_ocean") != nil)
        #expect(ThemeRegistry.shared.theme(for: "cyber_neon") != nil)
        #expect(ThemeRegistry.shared.theme(for: "glacier_blue") != nil)
        #expect(ThemeRegistry.shared.theme(for: "aurora_dream") != nil)
        #expect(ThemeRegistry.shared.theme(for: "midnight_gold") != nil)
    }

    @Test("查找不存在的 id 返回 nil")
    func testThemeLookupNotFound() {
        #expect(ThemeRegistry.shared.theme(for: "nonexistent") == nil)
    }

    @Test("旧主题 id 查找返回 nil（已移除）")
    func testOldThemeIdsReturnNil() {
        #expect(ThemeRegistry.shared.theme(for: "meadow_breeze") == nil)
        #expect(ThemeRegistry.shared.theme(for: "rose_dream") == nil)
        #expect(ThemeRegistry.shared.theme(for: "crimson_tech") == nil)
    }

    @Test("默认主题为青云薄荷")
    func testDefaultTheme() {
        #expect(ThemeRegistry.shared.defaultTheme.id == "mint_breeze")
    }

    @Test("Light 主题的 colorScheme 为 .light")
    func testLightThemesHaveLightScheme() {
        for id in ["mint_breeze", "glacier_blue"] {
            let theme = ThemeRegistry.shared.theme(for: id)
            #expect(theme?.colorScheme == .light, "\(id) should be .light")
        }
    }

    @Test("Dark 主题的 colorScheme 为 .dark")
    func testDarkThemesHaveDarkScheme() {
        for id in ["deep_ocean", "cyber_neon", "aurora_dream", "midnight_gold"] {
            let theme = ThemeRegistry.shared.theme(for: id)
            #expect(theme?.colorScheme == .dark, "\(id) should be .dark")
        }
    }

    @Test("重复 register 不会导致重复主题")
    func testDuplicateRegisterIgnored() {
        let before = ThemeRegistry.shared.allThemes.count
        ThemeRegistry.shared.register(.mintBreeze)
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

    @Test("mintBreeze 的 id 正确")
    func testMintBreezeId() {
        #expect(ThemeStyle.mintBreeze.id == "mint_breeze")
    }

    @Test("deepOcean 的 id 正确")
    func testDeepOceanId() {
        #expect(ThemeStyle.deepOcean.id == "deep_ocean")
    }

    @Test("cyberNeon 的 id 正确")
    func testCyberNeonId() {
        #expect(ThemeStyle.cyberNeon.id == "cyber_neon")
    }

    @Test("glacierBlue 的 id 正确")
    func testGlacierBlueId() {
        #expect(ThemeStyle.glacierBlue.id == "glacier_blue")
    }

    @Test("auroraDream 的 id 正确")
    func testAuroraDreamId() {
        #expect(ThemeStyle.auroraDream.id == "aurora_dream")
    }

    @Test("midnightGold 的 id 正确")
    func testMidnightGoldId() {
        #expect(ThemeStyle.midnightGold.id == "midnight_gold")
    }

    @Test("所有主题的 Identifiable id 不为空")
    func testIdentifiable() {
        let themes: [ThemeStyle] = [
            .mintBreeze, .deepOcean, .cyberNeon,
            .glacierBlue, .auroraDream, .midnightGold
        ]
        for style in themes {
            #expect(!style.id.isEmpty)
        }
    }

    @Test("ThemeStyle Equatable 基于 id 判等")
    func testEquatable() {
        #expect(ThemeStyle.mintBreeze == ThemeStyle.mintBreeze)
        #expect(ThemeStyle.mintBreeze != ThemeStyle.deepOcean)
    }

    @Test("所有主题均有 hasCustomBackground = true")
    func testAllThemesHaveCustomBackground() {
        let themes: [ThemeStyle] = [
            .mintBreeze, .deepOcean, .cyberNeon,
            .glacierBlue, .auroraDream, .midnightGold
        ]
        for style in themes {
            #expect(style.hasCustomBackground == true, "\(style.id) should have custom background")
        }
    }
}

// MARK: - ThemeColorPalette Tests

@Suite("ThemeColorPalette Tests")
struct ThemeColorPaletteTests {

    @Test("mintBreeze palette 所有颜色字段可被访问")
    func testMintBreezePaletteAccessible() {
        let palette = ThemeStyle.mintBreeze.palette
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
    }

    @Test("每个主题都有完整的 palette")
    func testEachStyleHasPalette() {
        let themes: [ThemeStyle] = [
            .mintBreeze, .deepOcean, .cyberNeon,
            .glacierBlue, .auroraDream, .midnightGold
        ]
        for style in themes {
            _ = style.palette.primary
            _ = style.palette.background
            _ = style.palette.textPrimary
            _ = style.palette.gradientStart
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

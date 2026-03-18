import Testing
import Foundation
import SwiftUI
@testable import TuneHaven

// MARK: - ColorMode Tests

@Suite("ColorMode Tests")
struct ColorModeTests {

    @Test("ColorMode 包含 3 种模式")
    func testColorModeCount() {
        #expect(ColorMode.allCases.count == 3)
    }

    @Test("system 模式的 colorScheme 为 nil（跟随系统）")
    func testSystemColorSchemeIsNil() {
        #expect(ColorMode.system.colorScheme == nil)
    }

    @Test("light 模式的 colorScheme 为 .light")
    func testLightColorScheme() {
        #expect(ColorMode.light.colorScheme == .light)
    }

    @Test("dark 模式的 colorScheme 为 .dark")
    func testDarkColorScheme() {
        #expect(ColorMode.dark.colorScheme == .dark)
    }

    @Test("所有 ColorMode 的 displayName 不为空")
    func testDisplayNamesNotEmpty() {
        for mode in ColorMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode) 的 displayName 不应为空")
        }
    }

    @Test("所有 ColorMode 的 iconName 不为空")
    func testIconNamesNotEmpty() {
        for mode in ColorMode.allCases {
            #expect(!mode.iconName.isEmpty, "\(mode) 的 iconName 不应为空")
        }
    }

    @Test("rawValue 从 0 开始连续")
    func testRawValues() {
        #expect(ColorMode.system.rawValue == 0)
        #expect(ColorMode.light.rawValue == 1)
        #expect(ColorMode.dark.rawValue == 2)
    }

    @Test("Identifiable 的 id 等于 rawValue")
    func testIdentifiableId() {
        #expect(ColorMode.system.id == 0)
        #expect(ColorMode.light.id == 1)
        #expect(ColorMode.dark.id == 2)
    }

    @Test("可从合法 rawValue 初始化")
    func testRawValueInit() {
        #expect(ColorMode(rawValue: 0) == .system)
        #expect(ColorMode(rawValue: 1) == .light)
        #expect(ColorMode(rawValue: 2) == .dark)
    }

    @Test("非法 rawValue 初始化返回 nil")
    func testInvalidRawValueReturnsNil() {
        #expect(ColorMode(rawValue: 99) == nil)
        #expect(ColorMode(rawValue: -1) == nil)
    }
}

// MARK: - ThemeRegistry Tests

@Suite("ThemeRegistry Tests")
struct ThemeRegistryTests {

    @Test("bootstrap 后注册表包含 6 个主题")
    func testAllThemesCount() {
        let registry = ThemeRegistry.shared
        registry.bootstrap()
        #expect(registry.allThemes.count == 6)
    }

    @Test("所有主题 id 唯一")
    func testAllThemeIdsUnique() {
        let registry = ThemeRegistry.shared
        registry.bootstrap()
        let ids = registry.allThemes.map { $0.id }
        #expect(ids.count == Set(ids).count)
    }

    @Test("所有主题 displayName 不为空")
    func testAllThemeDisplayNamesNotEmpty() {
        let registry = ThemeRegistry.shared
        registry.bootstrap()
        for theme in registry.allThemes {
            #expect(!theme.displayName.isEmpty, "主题 \(theme.id) 的 displayName 不应为空")
        }
    }

    @Test("可通过 id 查找主题")
    func testThemeLookup() {
        let registry = ThemeRegistry.shared
        registry.bootstrap()
        #expect(registry.theme(for: "meadow_breeze") != nil)
        #expect(registry.theme(for: "rose_dream") != nil)
        #expect(registry.theme(for: "frost_elegance") != nil)
        #expect(registry.theme(for: "crimson_tech") != nil)
        #expect(registry.theme(for: "comic_pop") != nil)
        #expect(registry.theme(for: "ink_wash") != nil)
    }

    @Test("查找不存在的 id 返回 nil")
    func testThemeLookupNotFound() {
        let registry = ThemeRegistry.shared
        registry.bootstrap()
        #expect(registry.theme(for: "nonexistent") == nil)
    }

    @Test("默认主题为翠野清风")
    func testDefaultTheme() {
        let registry = ThemeRegistry.shared
        #expect(registry.defaultTheme.id == "meadow_breeze")
    }
}

// MARK: - ThemeStyle Tests

@Suite("ThemeStyle Tests")
struct ThemeStyleTests {

    @Test("meadowBreeze 的 id 为 meadow_breeze")
    func testMeadowBreezeId() {
        #expect(ThemeStyle.meadowBreeze.id == "meadow_breeze")
    }

    @Test("roseDream 的 id 为 rose_dream")
    func testRoseDreamId() {
        #expect(ThemeStyle.roseDream.id == "rose_dream")
    }

    @Test("frostElegance 的 id 为 frost_elegance")
    func testFrostEleganceId() {
        #expect(ThemeStyle.frostElegance.id == "frost_elegance")
    }

    @Test("crimsonTech 的 id 为 crimson_tech")
    func testCrimsonTechId() {
        #expect(ThemeStyle.crimsonTech.id == "crimson_tech")
    }

    @Test("comicPop 的 id 为 comic_pop")
    func testComicPopId() {
        #expect(ThemeStyle.comicPop.id == "comic_pop")
    }

    @Test("inkWash 的 id 为 ink_wash")
    func testInkWashId() {
        #expect(ThemeStyle.inkWash.id == "ink_wash")
    }

    @Test("ThemeStyle 实现 Identifiable，id 不为空")
    func testIdentifiable() {
        let themes: [ThemeStyle] = [
            .meadowBreeze, .roseDream, .frostElegance,
            .crimsonTech, .comicPop, .inkWash
        ]
        for style in themes {
            #expect(!style.id.isEmpty)
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

    @Test("全零 HEX 可正常初始化（纯黑）")
    func testBlackHex() {
        _ = Color(hex: "#000000")
    }

    @Test("全 F HEX 可正常初始化（纯白）")
    func testWhiteHex() {
        _ = Color(hex: "#FFFFFF")
    }
}

// MARK: - SemanticColor Tests

@Suite("SemanticColor Tests")
struct SemanticColorTests {

    @Test("danger 颜色可正常初始化")
    func testDangerColor() {
        _ = SemanticColor.danger
    }

    @Test("warning 颜色可正常初始化")
    func testWarningColor() {
        _ = SemanticColor.warning
    }

    @Test("success 颜色可正常初始化")
    func testSuccessColor() {
        _ = SemanticColor.success
    }

    @Test("info 颜色可正常初始化")
    func testInfoColor() {
        _ = SemanticColor.info
    }

    @Test("dangerDark 颜色可正常初始化")
    func testDangerDarkColor() {
        _ = SemanticColor.dangerDark
    }

    @Test("warningDark 颜色可正常初始化")
    func testWarningDarkColor() {
        _ = SemanticColor.warningDark
    }

    @Test("successDark 颜色可正常初始化")
    func testSuccessDarkColor() {
        _ = SemanticColor.successDark
    }
}

// MARK: - ThemeColorPalette Tests

@Suite("ThemeColorPalette Tests")
struct ThemeColorPaletteTests {

    @Test("lightPalette 所有颜色字段可被访问")
    func testLightPaletteAccessible() {
        let palette = ThemeStyle.meadowBreeze.lightPalette
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

    @Test("darkPalette 所有颜色字段可被访问")
    func testDarkPaletteAccessible() {
        let palette = ThemeStyle.meadowBreeze.darkPalette
        _ = palette.primary
        _ = palette.background
        _ = palette.surface
        _ = palette.textPrimary
        _ = palette.secondary
        _ = palette.gradientStart
    }

    @Test("每个主题都有 lightPalette 和 darkPalette")
    func testEachStyleHasBothPalettes() {
        let themes: [ThemeStyle] = [
            .meadowBreeze, .roseDream, .frostElegance,
            .crimsonTech, .comicPop, .inkWash
        ]
        for style in themes {
            _ = style.lightPalette
            _ = style.darkPalette
        }
    }
}

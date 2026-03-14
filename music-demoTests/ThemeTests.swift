import Testing
import SwiftUI
@testable import music_demo

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

// MARK: - ThemeStyle Tests

@Suite("ThemeStyle Tests")
struct ThemeStyleTests {

    @Test("allStyles 包含 3 种内置主题")
    func testAllStylesCount() {
        #expect(ThemeStyle.allStyles.count == 3)
    }

    @Test("morandiGreen 的 id 为 morandi_green")
    func testMorandiGreenId() {
        #expect(ThemeStyle.morandiGreen.id == "morandi_green")
    }

    @Test("classicIndigo 的 id 为 classic_indigo")
    func testClassicIndigoId() {
        #expect(ThemeStyle.classicIndigo.id == "classic_indigo")
    }

    @Test("sakuraPink 的 id 为 sakura_pink")
    func testSakuraPinkId() {
        #expect(ThemeStyle.sakuraPink.id == "sakura_pink")
    }

    @Test("allStyles 中所有主题的 id 唯一")
    func testAllStyleIdsUnique() {
        let ids = ThemeStyle.allStyles.map { $0.id }
        #expect(ids.count == Set(ids).count)
    }

    @Test("allStyles 中所有主题的 displayName 不为空")
    func testAllStyleDisplayNamesNotEmpty() {
        for style in ThemeStyle.allStyles {
            #expect(!style.displayName.isEmpty, "主题 \(style.id) 的 displayName 不应为空")
        }
    }

    @Test("allStyles 包含 morandiGreen")
    func testAllStylesContainsMorandiGreen() {
        #expect(ThemeStyle.allStyles.contains { $0.id == "morandi_green" })
    }

    @Test("allStyles 包含 classicIndigo")
    func testAllStylesContainsClassicIndigo() {
        #expect(ThemeStyle.allStyles.contains { $0.id == "classic_indigo" })
    }

    @Test("allStyles 包含 sakuraPink")
    func testAllStylesContainsSakuraPink() {
        #expect(ThemeStyle.allStyles.contains { $0.id == "sakura_pink" })
    }

    @Test("ThemeStyle 实现 Identifiable，id 不为空")
    func testIdentifiable() {
        for style in ThemeStyle.allStyles {
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

    private var samplePalette: ThemeColorPalette {
        ThemeStyle.morandiGreen.lightPalette
    }

    @Test("lightPalette 所有颜色字段可被访问")
    func testLightPaletteAccessible() {
        let palette = ThemeStyle.morandiGreen.lightPalette
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
        let palette = ThemeStyle.morandiGreen.darkPalette
        _ = palette.primary
        _ = palette.background
        _ = palette.surface
        _ = palette.textPrimary
    }

    @Test("每个主题都有 lightPalette 和 darkPalette")
    func testEachStyleHasBothPalettes() {
        for style in ThemeStyle.allStyles {
            _ = style.lightPalette
            _ = style.darkPalette
        }
    }
}

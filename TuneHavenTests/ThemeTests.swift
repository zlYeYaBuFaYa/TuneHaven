import Testing
import Foundation
import SwiftUI
@testable import TuneHaven

// MARK: - ThemeRegistry Tests

@Suite("ThemeRegistry Tests", .serialized)
@MainActor
struct ThemeRegistryTests {

    init() {
        ThemeRegistry.shared.reset()
        ThemeRegistry.shared.bootstrap()
    }

    @Test("bootstrap 后注册表包含云霞、晴屿、月晕三套主题")
    func testAllThemes() {
        #expect(ThemeRegistry.shared.allThemes.map(\.id) == ["cloud_haze", "clear_isle", "moon_halo"])
        #expect(ThemeRegistry.shared.allThemes.map(\.displayName) == ["云霞", "晴屿", "月晕"])
    }

    @Test("默认主题为云霞")
    func testDefaultTheme() {
        #expect(ThemeRegistry.shared.defaultTheme.id == "cloud_haze")
    }

    @Test("旧主题 ID 换算为新主题")
    func testLegacyIDs() {
        let registry = ThemeRegistry.shared
        #expect(registry.canonicalID(for: "cloud_white") == "cloud_haze")
        #expect(registry.canonicalID(for: "azure_sky") == "clear_isle")
        #expect(registry.canonicalID(for: "twilight_rose") == "cloud_haze")
        #expect(registry.canonicalID(for: "cosmic_tech") == "moon_halo")
        #expect(registry.canonicalID(for: "moon_halo") == "moon_halo")
        #expect(registry.canonicalID(for: "nonexistent") == nil)
    }

    @Test("查找不存在的 id 返回 nil")
    func testThemeLookupNotFound() {
        #expect(ThemeRegistry.shared.theme(for: "nonexistent") == nil)
        #expect(ThemeRegistry.shared.theme(for: "cloud_white") == nil)
    }

    @Test("重复 register 不会导致重复主题")
    func testDuplicateRegisterIgnored() {
        let before = ThemeRegistry.shared.allThemes.count
        ThemeRegistry.shared.register(.cloudHaze)
        #expect(ThemeRegistry.shared.allThemes.count == before)
    }

    @Test("reset 后注册表为空")
    func testResetClearsAll() {
        ThemeRegistry.shared.reset()
        #expect(ThemeRegistry.shared.allThemes.isEmpty)
        ThemeRegistry.shared.bootstrap()
    }
}

// MARK: - ThemeManager 迁移

@Suite("ThemeManager 旧主题迁移", .serialized)
@MainActor
struct ThemeManagerMigrationTests {

    private func withStoredTheme(_ raw: String?, _ body: () -> Void) {
        let previous = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppStorageKey.themeStyle)
            } else {
                UserDefaults.standard.removeObject(forKey: AppStorageKey.themeStyle)
            }
        }
        if let raw {
            UserDefaults.standard.set(raw, forKey: AppStorageKey.themeStyle)
        } else {
            UserDefaults.standard.removeObject(forKey: AppStorageKey.themeStyle)
        }
        body()
    }

    @Test("启动时把旧主题 ID 换成新 ID 并写回偏好", arguments: [
        ("cloud_white", "cloud_haze"),
        ("azure_sky", "clear_isle"),
        ("twilight_rose", "cloud_haze"),
        ("cosmic_tech", "moon_halo"),
        ("midnight_gold", "cloud_haze"),
        ("garbage", "cloud_haze"),
    ])
    func testMigratesOnLaunch(raw: String, expected: String) {
        withStoredTheme(raw) {
            let manager = ThemeManager()
            #expect(manager.currentStyle.id == expected)
            #expect(UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) == expected)
        }
    }

    @Test("恢复旧备份写回旧主题 ID 后，reloadStoredStyle 换算为新主题")
    func testReloadMapsLegacyBackupValue() {
        withStoredTheme("clear_isle") {
            let manager = ThemeManager()
            UserDefaults.standard.set("cosmic_tech", forKey: AppStorageKey.themeStyle)
            manager.reloadStoredStyle()
            #expect(manager.currentStyle.id == "moon_halo")
            #expect(UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) == "moon_halo")
        }
    }

    @Test("三套主题都免费，任意切换立即生效并保存")
    func testAllThemesSelectable() {
        withStoredTheme(nil) {
            let manager = ThemeManager()
            for style in manager.allAvailableThemes {
                manager.setTheme(style)
                #expect(manager.currentStyle.id == style.id)
                #expect(UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) == style.id)
            }
        }
    }
}

// MARK: - ThemeStyle Tests

@Suite("ThemeStyle Tests")
struct ThemeStyleTests {

    private func hex(_ color: Color, _ scheme: ColorScheme) -> UInt32 {
        var env = EnvironmentValues()
        env.colorScheme = scheme
        let r = color.resolve(in: env)
        func c(_ v: Float) -> UInt32 { UInt32((Double(v) * 255).rounded()) }
        return (c(r.red) << 16) | (c(r.green) << 8) | c(r.blue)
    }

    @Test("ThemeStyle Equatable 基于 id 判等")
    func testEquatable() {
        #expect(ThemeStyle.cloudHaze == ThemeStyle.cloudHaze)
        #expect(ThemeStyle.cloudHaze != ThemeStyle.moonHalo)
    }

    @Test("三套主题都使用柔光背景")
    func testSoftGlowBackground() {
        for style in [ThemeStyle.cloudHaze, .clearIsle, .moonHalo] {
            #expect(style.visualConfig.backgroundType == .softGlow)
            #expect(style.hasCustomBackground)
        }
    }

    @Test("色板随系统深浅切换到对应令牌", arguments: [ThemeStyle.cloudHaze, .clearIsle, .moonHalo])
    func testPaletteFollowsColorScheme(style: ThemeStyle) {
        let p = style.palette
        #expect(hex(p.background, .light) == style.day.background)
        #expect(hex(p.background, .dark) == style.night.background)
        #expect(hex(p.textPrimary, .light) == style.day.textPrimary)
        #expect(hex(p.textPrimary, .dark) == style.night.textPrimary)
        #expect(hex(p.actionFill, .light) == style.day.actionFill)
        #expect(hex(p.actionFill, .dark) == style.night.actionFill)
        #expect(hex(p.primary, .dark) == style.night.accent)
        #expect(hex(p.glowA, .light) == style.day.glowA)
        #expect(hex(p.surface, .dark) == style.night.surfaceOpaque)
    }

    @Test("令牌与设计文档一致（抽查）")
    func testTokensMatchDesignDoc() {
        #expect(ThemeStyle.cloudHaze.day.accent == 0x5E4E88)
        #expect(ThemeStyle.clearIsle.night.background == 0x121C18)
        #expect(ThemeStyle.moonHalo.night.onAction == 0x242E48)
    }
}

// MARK: - Color+Hex Tests

@Suite("Color+Hex Tests")
struct ColorHexTests {

    private func rgb(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        let resolved = color.resolve(in: EnvironmentValues())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue), Double(resolved.opacity))
    }

    @Test("6 位 HEX #FF0000 解析为纯红")
    func testHex6Red() {
        let c = rgb(Color(hex: "#FF0000"))
        #expect(abs(c.r - 1.0) < 0.01, "红色分量应约为 1.0")
        #expect(abs(c.g) < 0.01, "绿色分量应约为 0")
        #expect(abs(c.b) < 0.01, "蓝色分量应约为 0")
    }

    @Test("6 位 HEX #FFFFFF 解析为白色")
    func testHex6White() {
        let c = rgb(Color(hex: "#FFFFFF"))
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g - 1.0) < 0.01)
        #expect(abs(c.b - 1.0) < 0.01)
    }

    @Test("6 位 HEX #000000 解析为黑色")
    func testHex6Black() {
        let c = rgb(Color(hex: "#000000"))
        #expect(abs(c.r) < 0.01)
        #expect(abs(c.g) < 0.01)
        #expect(abs(c.b) < 0.01)
    }

    @Test("6 位 HEX 不带 # 号可正常初始化并解析正确")
    func testHex6DigitWithoutHash() {
        let c = rgb(Color(hex: "FF0000"))
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g) < 0.01)
    }

    @Test("3 位 HEX #F00 扩展为纯红")
    func testHex3Digit() {
        let c = rgb(Color(hex: "#F00"))
        #expect(abs(c.r - 1.0) < 0.01)
        #expect(abs(c.g) < 0.01)
        #expect(abs(c.b) < 0.01)
    }

    @Test("8 位 HEX 含 alpha 通道正确解析")
    func testHex8Digit() {
        let c = rgb(Color(hex: "#80FF0000"))
        #expect(abs(c.r - 1.0) < 0.01, "红色分量应约为 1.0")
        #expect(abs(c.a - 0.502) < 0.02, "alpha 应约为 0.5 (0x80/0xFF≈0.502)")
    }

    @Test("小写 HEX 与大写等价")
    func testHexLowercase() {
        let u = rgb(Color(hex: "#FF0000"))
        let l = rgb(Color(hex: "#ff0000"))
        #expect(abs(u.r - l.r) < 0.01)
        #expect(abs(u.g - l.g) < 0.01)
        #expect(abs(u.b - l.b) < 0.01)
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

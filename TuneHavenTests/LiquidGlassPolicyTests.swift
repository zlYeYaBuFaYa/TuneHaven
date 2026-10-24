import Testing
import Foundation
@testable import TuneHaven

@Suite("Liquid Glass 分流")
struct LiquidGlassPolicyTests {

    @Test("iOS 26 且兼容键关闭才走玻璃")
    func glassRequiresNewOSAndNoCompatibilityKey() {
        #expect(LiquidGlassPolicy.usesLiquidGlassEffects(osIs26OrNewer: true, compatibilityMode: false))
        #expect(!LiquidGlassPolicy.usesLiquidGlassEffects(osIs26OrNewer: true, compatibilityMode: true))
        #expect(!LiquidGlassPolicy.usesLiquidGlassEffects(osIs26OrNewer: false, compatibilityMode: false))
        #expect(!LiquidGlassPolicy.usesLiquidGlassEffects(osIs26OrNewer: false, compatibilityMode: true))
    }

    @Test("兼容键开着时导航栏、Tab、sheet 都保持旧外观")
    func compatibilityKeepsLegacyChrome() {
        #expect(
            LiquidGlassPolicy.navigationBarSurface(
                osIs26OrNewer: true,
                compatibilityMode: true,
                customMaterial: false
            ) == .opaqueSurface
        )
        #expect(
            LiquidGlassPolicy.navigationBarSurface(
                osIs26OrNewer: true,
                compatibilityMode: true,
                customMaterial: true
            ) == .ultraThin
        )
        #expect(LiquidGlassPolicy.tabBarMaterial(osIs26OrNewer: true, compatibilityMode: true) == .ultraThin)
        #expect(
            LiquidGlassPolicy.sheetBackdrop(
                osIs26OrNewer: true,
                compatibilityMode: true,
                hasCustomBackground: false
            ) == .solidElevated
        )
    }

    @Test("关掉兼容键后，iOS 26 的纯色主题 sheet 交给系统，自绘背景仍用不透明底")
    func glassPathSheetDependsOnCustomBackground() {
        #expect(
            LiquidGlassPolicy.navigationBarSurface(
                osIs26OrNewer: true,
                compatibilityMode: false,
                customMaterial: true
            ) == .system
        )
        #expect(LiquidGlassPolicy.tabBarMaterial(osIs26OrNewer: true, compatibilityMode: false) == .glass)
        #expect(
            LiquidGlassPolicy.sheetBackdrop(
                osIs26OrNewer: true,
                compatibilityMode: false,
                hasCustomBackground: false
            ) == .system
        )
        #expect(
            LiquidGlassPolicy.sheetBackdrop(
                osIs26OrNewer: true,
                compatibilityMode: false,
                hasCustomBackground: true
            ) == .solidElevated
        )
    }

    @Test("iOS 18 即使关掉兼容键也不走玻璃")
    func olderSystemStaysLegacy() {
        #expect(
            LiquidGlassPolicy.navigationBarSurface(
                osIs26OrNewer: false,
                compatibilityMode: false,
                customMaterial: false
            ) == .opaqueSurface
        )
        #expect(
            LiquidGlassPolicy.navigationBarSurface(
                osIs26OrNewer: false,
                compatibilityMode: false,
                customMaterial: true
            ) == .ultraThin
        )
        #expect(LiquidGlassPolicy.tabBarMaterial(osIs26OrNewer: false, compatibilityMode: false) == .ultraThin)
        #expect(
            LiquidGlassPolicy.sheetBackdrop(
                osIs26OrNewer: false,
                compatibilityMode: false,
                hasCustomBackground: false
            ) == .solidElevated
        )
    }

    @Test("Info.plist 的布尔、数字和字符串都能识别兼容键")
    func parsesCompatibilityFlag() {
        #expect(LiquidGlassPolicy.compatibilityMode(infoValue: true))
        #expect(!LiquidGlassPolicy.compatibilityMode(infoValue: false))
        #expect(!LiquidGlassPolicy.compatibilityMode(infoValue: nil))
        #expect(LiquidGlassPolicy.compatibilityMode(infoValue: "YES"))
        #expect(LiquidGlassPolicy.compatibilityMode(infoValue: " true "))
        #expect(LiquidGlassPolicy.compatibilityMode(infoValue: "1"))
        #expect(!LiquidGlassPolicy.compatibilityMode(infoValue: "NO"))
        #expect(!LiquidGlassPolicy.compatibilityMode(infoValue: ""))
        #expect(LiquidGlassPolicy.compatibilityMode(infoValue: NSNumber(value: true)))
        #expect(!LiquidGlassPolicy.compatibilityMode(infoValue: NSNumber(value: false)))
    }
}

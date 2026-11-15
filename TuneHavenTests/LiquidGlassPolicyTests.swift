import Testing
import Foundation
@testable import TuneHaven

@Suite("Liquid Glass 分流")
struct LiquidGlassPolicyTests {

    @Test("iOS 26+ 导航栏和 Tab 交给玻璃，纯色主题 sheet 交给系统，自绘背景仍用不透明底")
    func newSystemUsesGlass() {
        #expect(LiquidGlassPolicy.navigationBarSurface(osIs26OrNewer: true, customMaterial: false) == .system)
        #expect(LiquidGlassPolicy.navigationBarSurface(osIs26OrNewer: true, customMaterial: true) == .system)
        #expect(LiquidGlassPolicy.tabBarMaterial(osIs26OrNewer: true) == .glass)
        #expect(LiquidGlassPolicy.sheetBackdrop(osIs26OrNewer: true, hasCustomBackground: false) == .system)
        #expect(LiquidGlassPolicy.sheetBackdrop(osIs26OrNewer: true, hasCustomBackground: true) == .solidElevated)
    }

    @Test("iOS 26 以下保持旧外观")
    func olderSystemStaysLegacy() {
        #expect(LiquidGlassPolicy.navigationBarSurface(osIs26OrNewer: false, customMaterial: false) == .opaqueSurface)
        #expect(LiquidGlassPolicy.navigationBarSurface(osIs26OrNewer: false, customMaterial: true) == .ultraThin)
        #expect(LiquidGlassPolicy.tabBarMaterial(osIs26OrNewer: false) == .ultraThin)
        #expect(LiquidGlassPolicy.sheetBackdrop(osIs26OrNewer: false, hasCustomBackground: false) == .solidElevated)
        #expect(LiquidGlassPolicy.sheetBackdrop(osIs26OrNewer: false, hasCustomBackground: true) == .solidElevated)
    }

    @Test("Info.plist 不再声明 UIDesignRequiresCompatibility")
    func compatibilityKeyRemoved() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") == nil)
    }
}

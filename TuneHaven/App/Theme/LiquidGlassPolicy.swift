import SwiftUI
import UIKit

/// Liquid Glass 第一阶段的分流。
///
/// 部署目标仍是 iOS 18。`#available(iOS 26, *)` 判断系统版本；
/// `UIDesignRequiresCompatibility` 本期留在 Info.plist，这里再读一次。
/// 键为真时保持旧外观。关掉键且系统为 iOS 26+ 才走玻璃路径。
/// 换 iOS 27 SDK 打包前必须删除该键。这里不改用系统 `TabView`。
enum LiquidGlassPolicy {
    enum NavigationBarSurface: Equatable {
        case system
        case ultraThin
        case opaqueSurface
    }

    enum TabBarMaterial: Equatable {
        case glass
        case ultraThin
    }

    enum SheetBackdrop: Equatable {
        case system
        case solidElevated
    }

    static func usesLiquidGlassEffects(osIs26OrNewer: Bool, compatibilityMode: Bool) -> Bool {
        osIs26OrNewer && !compatibilityMode
    }

    static func navigationBarSurface(
        osIs26OrNewer: Bool,
        compatibilityMode: Bool,
        customMaterial: Bool
    ) -> NavigationBarSurface {
        if usesLiquidGlassEffects(osIs26OrNewer: osIs26OrNewer, compatibilityMode: compatibilityMode) {
            return .system
        }
        return customMaterial ? .ultraThin : .opaqueSurface
    }

    static func tabBarMaterial(osIs26OrNewer: Bool, compatibilityMode: Bool) -> TabBarMaterial {
        usesLiquidGlassEffects(osIs26OrNewer: osIs26OrNewer, compatibilityMode: compatibilityMode) ? .glass : .ultraThin
    }

    static func sheetBackdrop(
        osIs26OrNewer: Bool,
        compatibilityMode: Bool,
        hasCustomBackground: Bool
    ) -> SheetBackdrop {
        let glass = usesLiquidGlassEffects(osIs26OrNewer: osIs26OrNewer, compatibilityMode: compatibilityMode)
        if glass && !hasCustomBackground {
            return .system
        }
        return .solidElevated
    }

    static var osIs26OrNewer: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }

    static let compatibilityModeEnabled: Bool = compatibilityMode(
        infoValue: Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility")
    )

    static var isLiquidGlassActive: Bool {
        usesLiquidGlassEffects(
            osIs26OrNewer: osIs26OrNewer,
            compatibilityMode: compatibilityModeEnabled
        )
    }

    static func compatibilityMode(infoValue: Any?) -> Bool {
        switch infoValue {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yes", "true", "1":
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    static func applyGlobalNavigationBarAppearance(surfaceColor: UIColor) {
        guard navigationBarSurface(
            osIs26OrNewer: osIs26OrNewer,
            compatibilityMode: compatibilityModeEnabled,
            customMaterial: false
        ) == .opaqueSurface else {
            return
        }
        let appearance = opaqueNavigationBarAppearance(surfaceColor: surfaceColor)
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
    }

    static func opaqueNavigationBarAppearance(surfaceColor: UIColor) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = surfaceColor
        appearance.shadowColor = .clear
        return appearance
    }

    static func apply(_ appearance: UINavigationBarAppearance, to bar: UINavigationBar) {
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
    }

    @ViewBuilder
    static func tabBarBackdrop(surfaceTint: Color) -> some View {
        if #available(iOS 26, *) {
            if isLiquidGlassActive {
                Rectangle()
                    .fill(Color.clear)
                    // surface 着色给标签一个稳定的深浅底，避免直接压在封面上。
                    .glassEffect(.regular.tint(surfaceTint.opacity(0.45)), in: Rectangle())
                    .ignoresSafeArea(edges: .bottom)
            } else {
                legacyTabBarBackdrop
            }
        } else {
            legacyTabBarBackdrop
        }
    }

    private static var legacyTabBarBackdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
    }
}

private struct ThemeNavigationBarSurfaceModifier: ViewModifier {
    var customMaterial: Bool
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        switch LiquidGlassPolicy.navigationBarSurface(
            osIs26OrNewer: LiquidGlassPolicy.osIs26OrNewer,
            compatibilityMode: LiquidGlassPolicy.compatibilityModeEnabled,
            customMaterial: customMaterial
        ) {
        case .system:
            content.toolbarBackground(Visibility.automatic, for: .navigationBar)
        case .ultraThin:
            content.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        case .opaqueSurface:
            content.toolbarBackground(palette.surface, for: .navigationBar)
        }
    }
}

extension View {
    /// 玻璃路径把导航栏交给系统；旧路径保持不透明 surface，自绘背景页保持超薄材质。
    func themeNavigationBarSurface(customMaterial: Bool = false) -> some View {
        modifier(ThemeNavigationBarSurfaceModifier(customMaterial: customMaterial))
    }

    @ViewBuilder
    func themeSheetPresentationBackground(elevated: Color, hasCustomBackground: Bool) -> some View {
        if LiquidGlassPolicy.sheetBackdrop(
            osIs26OrNewer: LiquidGlassPolicy.osIs26OrNewer,
            compatibilityMode: LiquidGlassPolicy.compatibilityModeEnabled,
            hasCustomBackground: hasCustomBackground
        ) == .system {
            self
        } else {
            self.presentationBackground(elevated)
        }
    }
}

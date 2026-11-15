import SwiftUI
import UIKit

/// Liquid Glass 分流。
///
/// 部署目标是 iOS 18。iOS 26 及以上走系统玻璃外观，更早的系统保持旧外观。
/// Info.plist 不再声明 `UIDesignRequiresCompatibility`：iOS 27 SDK 不再支持退回旧设计。
/// 这里不改用系统 `TabView`，Tab 栏仍由 `RootTabView` 自绘。
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

    static func navigationBarSurface(osIs26OrNewer: Bool, customMaterial: Bool) -> NavigationBarSurface {
        if osIs26OrNewer {
            return .system
        }
        return customMaterial ? .ultraThin : .opaqueSurface
    }

    static func tabBarMaterial(osIs26OrNewer: Bool) -> TabBarMaterial {
        osIs26OrNewer ? .glass : .ultraThin
    }

    static func sheetBackdrop(osIs26OrNewer: Bool, hasCustomBackground: Bool) -> SheetBackdrop {
        if osIs26OrNewer && !hasCustomBackground {
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

    static func applyGlobalNavigationBarAppearance(surfaceColor: UIColor) {
        guard navigationBarSurface(osIs26OrNewer: osIs26OrNewer, customMaterial: false) == .opaqueSurface else {
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
            Rectangle()
                .fill(Color.clear)
                // surface 着色给标签一个稳定的深浅底，避免直接压在封面上。
                .glassEffect(.regular.tint(surfaceTint.opacity(0.45)), in: Rectangle())
                .ignoresSafeArea(edges: .bottom)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct ThemeNavigationBarSurfaceModifier: ViewModifier {
    var customMaterial: Bool
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        switch LiquidGlassPolicy.navigationBarSurface(
            osIs26OrNewer: LiquidGlassPolicy.osIs26OrNewer,
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
            hasCustomBackground: hasCustomBackground
        ) == .system {
            self
        } else {
            self.presentationBackground(elevated)
        }
    }
}

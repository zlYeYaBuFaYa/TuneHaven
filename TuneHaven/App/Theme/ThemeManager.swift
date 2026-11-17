import SwiftUI

// MARK: - EnvironmentKey

struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.cloudHaze.palette
}

extension EnvironmentValues {
    var themePalette: ThemeColorPalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

// MARK: - ThemeManager

@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var currentStyle: ThemeStyle
    @AppStorage(AppStorageKey.themeStyle) private var storedThemeStyle: String = ThemeRegistry.shared.defaultTheme.id

    private let registry = ThemeRegistry.shared

    /// 更早版本的主题 ID，统一并入新的默认主题
    private static let retiredThemeIDs: Set<String> = [
        "meadow_breeze", "rose_dream", "frost_elegance", "crimson_tech", "comic_pop",
        "ink_wash", "deep_space_neon", "morandi_green", "classic_indigo", "sakura_pink",
        "minimal_pure", "warm_sunlight", "digital_mist", "mint_breeze", "deep_ocean",
        "cyber_neon", "glacier_blue", "aurora_dream", "midnight_gold",
    ]

    init() {
        registry.bootstrap()
        Self.migrateStoredThemeID(registry: registry)
        currentStyle = registry.resolveCurrentStyle()
    }

    /// 把偏好中的旧主题 ID 换成新 ID 并写回；无法识别的落回默认主题
    private static func migrateStoredThemeID(registry: ThemeRegistry) {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: AppStorageKey.themeStyle) else { return }
        let canonical = retiredThemeIDs.contains(raw)
            ? registry.defaultTheme.id
            : (registry.canonicalID(for: raw) ?? registry.defaultTheme.id)
        if canonical != raw {
            defaults.set(canonical, forKey: AppStorageKey.themeStyle)
        }
    }

    var palette: ThemeColorPalette { currentStyle.palette }

    var allAvailableThemes: [ThemeStyle] { registry.allThemes }

    /// 三套主题都免费，选中即生效并保存
    func setTheme(_ style: ThemeStyle) {
        currentStyle = style
        storedThemeStyle = style.id
        pendingFullApply = false
        scheduleWindowRefresh(delay: 0.3, fullApply: false)
    }

    /// 备份写回 `theme_style` 后刷新界面。旧主题 ID 换算为新 ID，无法识别的落回默认主题。
    func reloadStoredStyle() {
        Self.migrateStoredThemeID(registry: registry)
        if UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) == nil {
            UserDefaults.standard.set(registry.defaultTheme.id, forKey: AppStorageKey.themeStyle)
        }
        currentStyle = registry.resolveCurrentStyle()
        scheduleWindowRefresh(delay: 0.1, fullApply: true)
    }

    // MARK: - Window Management

    func applyToWindows() {
        guard let windowScene = Self.foregroundWindowScene else {
            AppLogger.shared.debug("[ThemeManager] applyToWindows — no foreground windowScene yet")
            return
        }
        let bgColor = UIColor(currentStyle.palette.background)
        let surfaceColor = UIColor(currentStyle.palette.surface)

        AppLogger.shared.debug("[ThemeManager] applyToWindows — theme=\(currentStyle.id)")

        // 深浅外观跟随系统：不覆盖 userInterfaceStyle，动态色随系统切换
        windowScene.windows.forEach { window in
            window.backgroundColor = bgColor
            window.overrideUserInterfaceStyle = .unspecified
            Self.updateNavigationBars(on: window.rootViewController, surfaceColor: surfaceColor)
        }
    }

    func refreshWindows() {
        guard let windowScene = Self.foregroundWindowScene else {
            AppLogger.shared.debug("[ThemeManager] refreshWindows — no foreground windowScene")
            return
        }
        let bgColor = UIColor(currentStyle.palette.background)
        let surfaceColor = UIColor(currentStyle.palette.surface)

        AppDelegate.applyNavigationBarAppearance(surfaceColor: surfaceColor)

        windowScene.windows.forEach { window in
            window.backgroundColor = bgColor
            window.overrideUserInterfaceStyle = .unspecified
        }
        AppLogger.shared.debug("[ThemeManager] refreshWindows done — theme=\(currentStyle.id)")
    }

    private static var foregroundWindowScene: UIWindowScene? {
        let allScenes: [UIWindowScene] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let foreground = allScenes.first {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
        return foreground ?? allScenes.first
    }

    // MARK: - Deferred Refresh

    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingFullApply: Bool = false

    func scheduleWindowRefresh(delay: TimeInterval = 0.15, fullApply: Bool = true) {
        if fullApply { pendingFullApply = true }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if self.pendingFullApply {
                self.applyToWindows()
            } else {
                self.refreshWindows()
            }
            self.pendingFullApply = false
        }
    }

    // MARK: - Reactive Palette Injection

    struct PaletteInjector: ViewModifier {
        @ObservedObject var themeManager: ThemeManager

        func body(content: Content) -> some View {
            content
                .environment(\.themePalette, themeManager.palette)
        }
    }

    // MARK: - Navigation Bar

    private static func updateNavigationBars(on vc: UIViewController?, surfaceColor: UIColor) {
        guard let vc = vc else { return }
        let surface = LiquidGlassPolicy.navigationBarSurface(
            osIs26OrNewer: LiquidGlassPolicy.osIs26OrNewer,
            customMaterial: false
        )
        guard surface == .opaqueSurface else { return }
        if let nav = vc as? UINavigationController {
            let appearance = LiquidGlassPolicy.opaqueNavigationBarAppearance(surfaceColor: surfaceColor)
            LiquidGlassPolicy.apply(appearance, to: nav.navigationBar)
        }
        for child in vc.children {
            updateNavigationBars(on: child, surfaceColor: surfaceColor)
        }
        if let presented = vc.presentedViewController {
            updateNavigationBars(on: presented, surfaceColor: surfaceColor)
        }
    }
}

// MARK: - View Extension

extension View {
    func injectThemePalette(from themeManager: ThemeManager) -> some View {
        modifier(ThemeManager.PaletteInjector(themeManager: themeManager))
    }
}

import SwiftUI

// MARK: - EnvironmentKey

struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.cloudWhite.palette
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

    private static let legacyMapping: [String: String] = [
        "meadow_breeze":   "cloud_white",
        "rose_dream":      "cloud_white",
        "frost_elegance":  "cloud_white",
        "crimson_tech":    "cloud_white",
        "comic_pop":       "cloud_white",
        "ink_wash":        "cloud_white",
        "deep_space_neon": "cloud_white",
        "morandi_green":   "cloud_white",
        "classic_indigo":  "cloud_white",
        "sakura_pink":     "cloud_white",
        "minimal_pure":    "cloud_white",
        "warm_sunlight":   "cloud_white",
        "digital_mist":    "cloud_white",
        "mint_breeze":     "cloud_white",
        "deep_ocean":      "cloud_white",
        "cyber_neon":      "cloud_white",
        "glacier_blue":    "cloud_white",
        "aurora_dream":    "cloud_white",
        "midnight_gold":   "cloud_white",
    ]

    init() {
        registry.bootstrap()

        let rawId = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) ?? registry.defaultTheme.id
        if let migrated = Self.legacyMapping[rawId] {
            UserDefaults.standard.set(migrated, forKey: AppStorageKey.themeStyle)
        }

        currentStyle = registry.resolveCurrentStyle()
    }

    private static let freeThemeIDs: Set<String> = ["cloud_white", "azure_sky"]

    private var tierInitialized = false
    var currentTier: SubscriptionTier = .free {
        didSet {
            guard tierInitialized, oldValue != currentTier else {
                tierInitialized = true
                return
            }
            if currentTier == .free && !Self.freeThemeIDs.contains(currentStyle.id) {
                setTheme(.cloudWhite)
            }
        }
    }

    func isPremiumTheme(_ style: ThemeStyle) -> Bool {
        !Self.freeThemeIDs.contains(style.id)
    }

    var palette: ThemeColorPalette { currentStyle.palette }

    var colorScheme: ColorScheme { currentStyle.colorScheme }

    var allAvailableThemes: [ThemeStyle] { registry.allThemes }

    func setTheme(_ style: ThemeStyle) {
        currentStyle = style
        storedThemeStyle = style.id
        pendingFullApply = false
        scheduleWindowRefresh(delay: 0.3, fullApply: false)
    }

    // MARK: - Window Management

    func applyToWindows() {
        applyThemeToWindows(fullApply: true)
    }

    func refreshWindows() {
        applyThemeToWindows(fullApply: false)
    }

    private func applyThemeToWindows(fullApply: Bool) {
        guard let windowScene = Self.foregroundWindowScene else {
            AppLogger.shared.debug("[ThemeManager] applyThemeToWindows — no foreground windowScene")
            return
        }
        let bgColor = UIColor(currentStyle.palette.background)
        let surfaceColor = UIColor(currentStyle.palette.surface)
        let uiStyle: UIUserInterfaceStyle = currentStyle.colorScheme == .dark ? .dark : .light

        if !fullApply {
            AppDelegate.applyNavigationBarAppearance(surfaceColor: surfaceColor)
        }

        windowScene.windows.forEach { window in
            window.backgroundColor = bgColor
            window.overrideUserInterfaceStyle = uiStyle
            if fullApply {
                Self.updateNavigationBars(on: window.rootViewController, surfaceColor: surfaceColor)
            }
        }
        AppLogger.shared.debug("[ThemeManager] applyThemeToWindows(fullApply=\(fullApply)) — theme=\(currentStyle.id)")
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
                .preferredColorScheme(themeManager.colorScheme)
        }
    }

    // MARK: - Navigation Bar

    private static func updateNavigationBars(on vc: UIViewController?, surfaceColor: UIColor) {
        guard let vc = vc else { return }
        if let nav = vc as? UINavigationController {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = surfaceColor
            appearance.shadowColor = .clear
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.compactAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
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

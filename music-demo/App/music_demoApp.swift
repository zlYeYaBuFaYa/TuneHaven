import SwiftUI
import AVFoundation

@main
struct music_demoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var libraryService = MusicLibraryService()
    @StateObject private var playlistService = PlaylistService()
    @StateObject private var importService = ImportService()
    @StateObject private var searchService = SearchService()
    @StateObject private var router = AppRouter()
    @StateObject private var snackbar = SnackbarState()
    @StateObject private var wallpaperManager = WallpaperManager()

    private let playbackService = PlaybackService.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var isReady = false
    @State private var initError: String?
    @State private var paletteScheme: ColorScheme = {
        let mode = ColorMode(rawValue: UserDefaults.standard.integer(forKey: "color_mode")) ?? .system
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system:
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                resolvedPalette.background
                    .ignoresSafeArea()

                if isReady {
                    RootTabView()
                        .environmentObject(themeManager)
                        .environmentObject(libraryService)
                        .environmentObject(playlistService)
                        .environmentObject(importService)
                        .environmentObject(searchService)
                        .environmentObject(router)
                        .environmentObject(snackbar)
                        .environmentObject(wallpaperManager)
                        .environment(\.themePalette, resolvedPalette)
                        .snackbar(snackbar)
                } else if let error = initError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("启动失败")
                            .font(.title2.bold())
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ProgressView("加载中...")
                        .progressViewStyle(.circular)
                }
            }
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .task { await initialize() }
            .onAppear {
                AppLogger.shared.debug("[App] onAppear — applying window theme")
                themeManager.applyToWindows()
                refreshPaletteScheme()
            }
            .onChange(of: themeManager.colorMode) { _, newMode in
                AppLogger.shared.debug("[App] colorMode changed → \(newMode)")
                themeManager.applyToWindows()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    refreshPaletteScheme()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                AppLogger.shared.debug("[App] scenePhase → \(phase)")
                switch phase {
                case .active:
                    playbackService.checkSleepTimerOnForeground()
                    themeManager.applyToWindows()
                    refreshPaletteScheme()
                case .background:
                    AudioSessionManager.shared.ensureActive()
                default:
                    break
                }
            }
        }
    }

    private var resolvedPalette: ThemeColorPalette {
        themeManager.resolvedPalette(for: paletteScheme)
    }

    private func refreshPaletteScheme() {
        let scheme: ColorScheme
        switch themeManager.colorMode {
        case .light:
            scheme = .light
        case .dark:
            scheme = .dark
        case .system:
            let systemDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
            scheme = systemDark ? .dark : .light
        }
        if paletteScheme != scheme {
            paletteScheme = scheme
        }
    }

    private func initialize() async {
        do {
            AppLogger.shared.info("[App] initialize start")
            MigrationManager.shared.runVersionUpgradeTasks()
            try await CoreDataStack.shared.load()
            SandboxPathManager.createAllDirectories()
            try await playlistService.initializeSystemPlaylists()
            await libraryService.loadSongs()
            await libraryService.cleanupOnLaunch()
            playbackService.checkSleepTimerOnForeground()
            isReady = true
            AppLogger.shared.info("[App] initialize done — isReady=true, scheduling UIKit background refresh")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                themeManager.applyToWindows()
            }
        } catch {
            initError = error.localizedDescription
            AppLogger.shared.error("[App] initialize FAILED: \(error)")
        }
    }
}

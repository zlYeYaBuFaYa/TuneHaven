import SwiftUI
import AVFoundation

@main
struct TuneHavenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var libraryService = MusicLibraryService()
    @StateObject private var playlistService = PlaylistService()
    @StateObject private var importService = ImportService()
    @StateObject private var searchService = SearchService()
    @StateObject private var router = AppRouter()
    @StateObject private var snackbar = SnackbarState()
    @StateObject private var wallpaperManager = WallpaperManager()
    @StateObject private var groupService = PlaylistGroupService()
    @StateObject private var webDAVService = WebDAVService()

    private let playbackService = PlaybackService.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var isReady = false
    @State private var initError: String?
    @State private var pendingImportURLs: [URL] = []
    @State private var openInHandler: OpenInImportHandler?
    @State private var paletteScheme: ColorScheme = {
        let mode = ColorMode(rawValue: UserDefaults.standard.integer(forKey: AppStorageKey.colorMode)) ?? .system
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let style = UITraitCollection.current.userInterfaceStyle
            return style == .dark ? .dark : .light
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
                        .environmentObject(groupService)
                        .environmentObject(playbackService)
                        .environmentObject(AudioEngine.shared)
                        .environmentObject(webDAVService)
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
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onAppear {
                AppLogger.shared.debug("[App] onAppear — applying window theme")
                refreshPaletteScheme()
                themeManager.scheduleWindowRefresh(delay: 0.1, fullApply: true)
            }
            .onChange(of: themeManager.colorMode) { _, newMode in
                AppLogger.shared.debug("[App] colorMode changed → \(newMode)")
                refreshPaletteScheme()
                themeManager.scheduleWindowRefresh(delay: 0.1, fullApply: true)
            }
            .onChange(of: scenePhase) { _, phase in
                AppLogger.shared.debug("[App] scenePhase → \(phase)")
                switch phase {
                case .active:
                    playbackService.checkSleepTimerOnForeground()
                    refreshPaletteScheme()
                case .inactive:
                    refreshPaletteScheme()
                case .background:
                    AudioSessionManager.shared.ensureActive()
                @unknown default:
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
            let style = UITraitCollection.current.userInterfaceStyle
            scheme = style == .dark ? .dark : .light
        }
        if paletteScheme != scheme {
            paletteScheme = scheme
        }
    }

    private func handleIncomingURL(_ url: URL) {
        AppLogger.shared.info("[App] onOpenURL: \(url.lastPathComponent)")
        guard isReady else {
            pendingImportURLs.append(url)
            return
        }
        ensureOpenInHandler().enqueue(url: url)
    }

    private func ensureOpenInHandler() -> OpenInImportHandler {
        if let handler = openInHandler { return handler }
        let handler = OpenInImportHandler(
            importService: importService,
            libraryService: libraryService,
            snackbar: snackbar
        )
        openInHandler = handler
        return handler
    }

    private func initialize() async {
        do {
            AppLogger.shared.info("[App] initialize start")
            playbackService.configure(libraryService: libraryService)
            MigrationManager.shared.runVersionUpgradeTasks()
            try await CoreDataStack.shared.load()
            SandboxPathManager.createAllDirectories()
            try await playlistService.initializeSystemPlaylists()
            await libraryService.loadSongs()
            await libraryService.cleanupOnLaunch()
            OpenInImportHandler.cleanupInbox()
            playbackService.checkSleepTimerOnForeground()
            isReady = true
            AppLogger.shared.info("[App] initialize done — isReady=true, scheduling UIKit background refresh")

            if !pendingImportURLs.isEmpty {
                let urls = pendingImportURLs
                pendingImportURLs.removeAll()
                ensureOpenInHandler().enqueue(urls: urls)
            }

            themeManager.scheduleWindowRefresh(delay: 0.15, fullApply: true)
        } catch {
            initError = error.localizedDescription
            AppLogger.shared.error("[App] initialize FAILED: \(error)")
        }
    }
}

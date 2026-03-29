import SwiftUI

@main
struct TuneHavenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var container = AppDIContainer()

    @Environment(\.scenePhase) private var scenePhase
    @State private var isReady = false
    @State private var isInitializing = false
    @State private var initError: String?
    @State private var pendingImportURLs: [URL] = []
    @State private var openInHandler: OpenInImportHandler?

    var body: some Scene {
        WindowGroup {
            ZStack {
                container.themeManager.palette.background
                    .ignoresSafeArea()

                if isReady {
                    RootTabView()
                        .environmentObject(container.themeManager)
                        .environmentObject(container.libraryService)
                        .environmentObject(container.playlistService)
                        .environmentObject(container.importService)
                        .environmentObject(container.searchService)
                        .environmentObject(container.router)
                        .environmentObject(container.snackbar)
                        .environmentObject(container.groupService)
                        .environmentObject(container.playbackService)
                        .environmentObject(container.audioEngine)
                        .environmentObject(container.webDAVService)
                        .environmentObject(container.lyricsService)
                        .environment(\.imageCache, ImageCacheManager.shared)
                        .injectThemePalette(from: container.themeManager)
                        .snackbar(container.snackbar)
                        .transition(.identity)
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
            .animation(nil, value: isReady)
            .task { await initialize() }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onAppear {
                AppLogger.shared.debug("[App] onAppear — applying window theme")
                container.themeManager.scheduleWindowRefresh(delay: 0.1, fullApply: true)
            }
            .onChange(of: scenePhase) { phase in
                AppLogger.shared.debug("[App] scenePhase → \(phase)")
                switch phase {
                case .active:
                    container.playbackService.checkSleepTimerOnForeground()
                case .background:
                    container.audioSessionManager.ensureActive()
                default:
                    break
                }
            }
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
            importService: container.importService,
            libraryService: container.libraryService,
            fileStorage: FileStorageService.shared,
            snackbar: container.snackbar
        )
        openInHandler = handler
        return handler
    }

    private func initialize() async {
        guard !isReady && !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }

        do {
            AppLogger.shared.info("[App] initialize start")
            try await container.bootstrap()
            try await container.playlistService.initializeSystemPlaylists()
            await container.libraryService.loadSongs()
            await container.libraryService.cleanupOnLaunch()
            container.playbackService.checkSleepTimerOnForeground()
            isReady = true
            AppLogger.shared.info("[App] initialize done — isReady=true")

            if !pendingImportURLs.isEmpty {
                let urls = pendingImportURLs
                pendingImportURLs.removeAll()
                ensureOpenInHandler().enqueue(urls: urls)
            }

            container.themeManager.scheduleWindowRefresh(delay: 0.15, fullApply: true)
        } catch {
            initError = error.localizedDescription
            AppLogger.shared.error("[App] initialize FAILED: \(error)")
        }
    }
}

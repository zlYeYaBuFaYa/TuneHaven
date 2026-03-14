import SwiftUI

@main
struct music_demoApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var libraryService = MusicLibraryService()
    @StateObject private var playlistService = PlaylistService()
    @StateObject private var importService = ImportService()
    @StateObject private var searchService = SearchService()
    @StateObject private var router = AppRouter()
    @StateObject private var snackbar = SnackbarState()

    // 读取系统颜色模式，配合 ThemeManager 解析出正确色板
    @Environment(\.colorScheme) private var systemColorScheme

    private let playbackService = PlaybackService.shared

    @State private var isReady = false
    @State private var initError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    RootTabView()
                        .environmentObject(themeManager)
                        .environmentObject(libraryService)
                        .environmentObject(playlistService)
                        .environmentObject(importService)
                        .environmentObject(searchService)
                        .environmentObject(router)
                        .environmentObject(snackbar)
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
        }
    }

    private var resolvedPalette: ThemeColorPalette {
        themeManager.resolvedPalette(for: systemColorScheme)
    }

    private func initialize() async {
        do {
            MigrationManager.shared.runVersionUpgradeTasks()
            try await CoreDataStack.shared.load()
            SandboxPathManager.createAllDirectories()
            try? AudioSessionManager.shared.configure()
            try await playlistService.initializeSystemPlaylists()
            await libraryService.loadSongs()
            await libraryService.cleanupOnLaunch()
            playbackService.checkSleepTimerOnForeground()
            isReady = true
        } catch {
            initError = error.localizedDescription
        }
    }
}

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
                        .environmentObject(container.shareService)
                        .environmentObject(container.backupService)
                        .environmentObject(container.subscriptionService)
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
                    Task { await container.subscriptionService.refreshStatus() }
                case .background:
                    container.audioSessionManager.ensureActive()
                default:
                    break
                }
            }
        }
    }

    /// 播放器或其它 sheet 还在时，等它们收起后再弹恢复页。不调用播放控制。
    @MainActor
    private static func presentStagedBackup(
        _ url: URL,
        handoff: ExternalBackupHandoff,
        router: AppRouter,
        backupService: BackupRestoreService,
        snackbar: SnackbarState
    ) {
        ExternalBackupOpen.begin(
            url: url,
            handoff: handoff,
            router: router,
            backupService: backupService,
            snackbar: snackbar
        )
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
        let backupService = container.backupService
        let router = container.router
        let snackbar = container.snackbar
        let handler = OpenInImportHandler(
            importService: container.importService,
            libraryService: container.libraryService,
            fileStorage: FileStorageService.shared,
            snackbar: container.snackbar,
            onBackupPackage: { url in
                guard let staged = backupService.stageExternalPackage(url) else { return false }
                let handoff = router.relinquishModalsForExternalBackup()
                router.selectedTab = .settings
                Self.presentStagedBackup(
                    staged,
                    handoff: handoff,
                    router: router,
                    backupService: backupService,
                    snackbar: snackbar
                )
                return true
            }
        )
        openInHandler = handler
        return handler
    }

    private func recordFirstLaunchDateIfNeeded() {
        let key = AppStorageKey.appFirstLaunchDate
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(Date(), forKey: key)
        }
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
            recordFirstLaunchDateIfNeeded()
            await container.subscriptionService.initialize()
            container.setupSubscriptionBindings()
            await container.playbackService.restoreLastPlayedSong()
            isReady = true
            AppLogger.shared.info("[App] initialize done — isReady=true")

            // bootstrap 里的备份临时目录清理已经结束。这之后才处理冷启动积压的打开请求。
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

/// 从「文件」打开备份后的弹出。收起动画期间若又被别的模态占住，本次不弹。
/// 恢复页自己的 `onAppear` 才算已经弹出。没出现的打开由超时兜底放开，副本留在 incoming。
@MainActor
enum ExternalBackupOpen {
    static let modalOccupiedNotice = "备份已暂存。请关闭当前页面后，再从「文件」打开"

    /// `settle` 和 `presentationTimeout` 仅供测试缩短等待。正式路径用默认值。
    @discardableResult
    static func begin(
        url: URL,
        handoff: ExternalBackupHandoff,
        router: AppRouter,
        backupService: BackupRestoreService,
        snackbar: SnackbarState,
        settle: Duration = AppRouter.externalBackupDismissSettle,
        presentationTimeout: Duration = AppRouter.externalBackupPresentationTimeout
    ) -> Task<Void, Never> {
        let timeoutTask = router.scheduleExternalBackupPresentationTimeout(
            token: handoff.token,
            timeout: presentationTimeout,
            onReleased: {
                AppLogger.shared.info("[Backup] 恢复页没有出现，放弃本次并放开模态层")
                backupService.retractUnconfirmedExternalRestore(token: handoff.token)
                snackbar.show(message: modalOccupiedNotice)
            }
        )
        let show = {
            attemptShow(
                url: url,
                token: handoff.token,
                router: router,
                backupService: backupService,
                snackbar: snackbar
            )
        }
        guard handoff.needsDelay else {
            show()
            return timeoutTask
        }
        Task { @MainActor in
            try? await Task.sleep(for: settle)
            guard router.isCurrentExternalBackup(handoff.token) else { return }
            if handoff.playerWasPresented {
                router.closePlayer()
                try? await Task.sleep(for: settle)
                guard router.isCurrentExternalBackup(handoff.token) else { return }
            }
            show()
        }
        return timeoutTask
    }

    static func attemptShow(
        url: URL,
        token: Int,
        router: AppRouter,
        backupService: BackupRestoreService,
        snackbar: SnackbarState
    ) {
        switch router.resolveExternalBackupShow(token: token) {
        case .present:
            backupService.presentRestore(url: url, externalBackupToken: token)
        case .abandonModalOccupied:
            AppLogger.shared.info("[Backup] 交接结束时已有其它页面，放弃本次恢复页")
            snackbar.show(message: modalOccupiedNotice)
        case .superseded:
            break
        }
    }

    /// 恢复页 `onAppear` 调用。只确认这份 presentation 自己的 token。
    static func noteRestoreAppeared(
        presentation: BackupPresentation,
        router: AppRouter,
        backupService: BackupRestoreService
    ) {
        guard presentation.kind == .restore, let token = presentation.externalBackupToken else { return }
        router.confirmExternalBackupAppeared(token: token)
        backupService.acknowledgeExternalRestoreAppeared(token: token)
    }
}

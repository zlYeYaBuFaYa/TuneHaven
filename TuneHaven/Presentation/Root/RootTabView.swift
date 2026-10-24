import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var snackbar: SnackbarState
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @EnvironmentObject private var lyricsService: LyricsService
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var backupService: BackupRestoreService
    @Environment(\.themePalette) private var palette

    private var hasCustomBg: Bool {
        themeManager.currentStyle.hasCustomBackground
    }

    var body: some View {
        ZStack {
            ThemeBackgroundView()

            LibraryTabView()
                .opacity(router.selectedTab == .library ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .library)

            PlaylistTabView()
                .opacity(router.selectedTab == .playlist ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .playlist)

            SettingsTabView()
                .opacity(router.selectedTab == .settings ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .settings)
        }
        .environment(\.hasCustomBackground, hasCustomBg)
        .animation(nil, value: router.selectedTab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                MiniPlayerBar()
                customTabBar
            }
        }
        .fullScreenCover(isPresented: .init(
            get:  { router.isPlayerPresented },
            set:  { router.isPlayerPresented = $0 }
        )) {
            injectPresentedEnvironment(
                PlayerView()
                    // 播放器文字落在色板渐变上。玻璃路径也保留这块不透明底，避免曲库透出来。
                    .presentationBackground(
                        LinearGradient(
                            colors: [themeManager.palette.background, themeManager.palette.surfaceSecondary, themeManager.palette.highlight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
        }
        .sheet(item: $router.sheet) { destination in
            injectPresentedEnvironment(
                sheetView(for: destination)
                    .themeSheetPresentationBackground(
                        elevated: themeManager.palette.elevatedSurface,
                        hasCustomBackground: hasCustomBg
                    )
            )
        }
        .sheet(item: Binding(
            get: { backupService.presentation },
            set: { newValue in
                backupService.handlePresentationChange(to: newValue)
                if newValue == nil, backupService.shouldReleaseExternalModal {
                    router.finishExternalBackupPresentation()
                }
            }
        )) { presentation in
            BackupCenterView(presentation: presentation)
                .environmentObject(backupService)
                .environment(\.themePalette, themeManager.palette)
        }
        .onChange(of: playback.losslessBlockedSong) { blocked in
            guard let blocked else { return }
            let playback = playback
            let router = router
            Task { @MainActor in
                // 曲库点播会在拦截之后立刻 openPlayer()。稍等再决定由谁弹墙，
                // 避免 sheet 落在 fullScreenCover 下面。播放器打开时由 PlayerView 接手。
                // 从文件打开备份时，这次付费墙让出模态层，不跟恢复页抢。
                try? await Task.sleep(for: .seconds(0.35))
                guard playback.losslessBlockedSong?.id == blocked.id else { return }
                if router.externalBackupTakesModal {
                    playback.clearLosslessBlock()
                    return
                }
                if router.isPlayerPresented { return }
                playback.clearLosslessBlock()
                router.present(.paywall(feature: .losslessPlayback))
            }
        }
        .onAppear {
            #if DEBUG
            AppLogger.shared.debug("[RootTabView] onAppear — palette.background=\(palette.background)")
            #endif
        }
    }

    // MARK: - Custom Tab Bar

    private var customTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(.library, label: "音乐库")
                tabButton(.playlist, label: "歌单")
                tabButton(.settings, label: "设置")
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background {
            LiquidGlassPolicy.tabBarBackdrop(surfaceTint: palette.surface)
        }
    }

    private func tabButton(_ tab: AppTab, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                #if DEBUG
                AppLogger.shared.debug("[RootTabView] tab switch: \(router.selectedTab) → \(tab)")
                #endif
                router.selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: router.selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(router.selectedTab == tab ? palette.primary : palette.textSecondary)
                Circle()
                    .fill(router.selectedTab == tab ? palette.primary : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func injectPresentedEnvironment<V: View>(_ content: V) -> some View {
        content
            .withFullEnvironment(
                themeManager: themeManager,
                router: router,
                libraryService: libraryService,
                playlistService: playlistService,
                snackbar: snackbar,
                playback: playback,
                engine: engine,
                lyricsService: lyricsService,
                subscriptionService: subscriptionService
            )
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetView(for destination: SheetDestination) -> some View {
        switch destination {
        case .createPlaylist:
            CreatePlaylistSheet()
        case .addToPlaylist(let ids):
            AddToPlaylistSheet(songIds: ids)
        case .editPlaylist(let id):
            EditPlaylistSheet(playlistId: id)
        case .setSleepTimer:
            SleepTimerSheet()
        case .playbackSpeedPicker:
            PlaybackSpeedSheet()
        case .importFromFiles:
            ImportFilesView()
        case .playlistCoverPicker(let id):
            PlaylistCoverPickerSheet(playlistId: id)
        case .batchAddSongs(let id):
            BatchAddSongsView(playlistId: id)
        case .paywall(let feature):
            PaywallView(triggerFeature: feature)
        }
    }
}

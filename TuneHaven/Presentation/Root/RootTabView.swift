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
            VStack(spacing: 8) {
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

    /// 图标加文字的悬浮底栏（docs/UI设计文档.md §5.2、§6；交互设计文档 §2.1）。
    /// 选中态同时体现在符号、胶囊底和可访问语义上。
    private var customTabBar: some View {
        HStack(spacing: 4) {
            tabButton(.library, label: "音乐库", symbol: "music.note.list")
            tabButton(.playlist, label: "歌单", symbol: "music.note")
            tabButton(.settings, label: "设置", symbol: "gearshape")
        }
        .padding(6)
        .background {
            LiquidGlassPolicy.floatingBarBackdrop(surfaceTint: palette.surface, cornerRadius: 26)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppTab, label: String, symbol: String) -> some View {
        let isSelected = router.selectedTab == tab
        return Button {
            // 再次点击当前 Tab 不触发额外行为（交互设计文档 §2.1）
            guard !isSelected else { return }
            router.selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? Self.selectedSymbol(symbol) : symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .frame(height: 24)
                Text(label)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? palette.textPrimary : palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if isSelected {
                    Capsule().fill(palette.textPrimary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 选中时优先实心符号；没有实心版本的保持原样
    private static func selectedSymbol(_ symbol: String) -> String {
        UIImage(systemName: symbol + ".fill") != nil ? symbol + ".fill" : symbol
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

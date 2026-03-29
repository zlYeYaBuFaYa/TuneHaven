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
            PlayerView()
                .presentationBackground(
                    LinearGradient(
                        colors: [themeManager.palette.background, themeManager.palette.surfaceSecondary, themeManager.palette.highlight],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .withFullEnvironment(
                    themeManager: themeManager,
                    router: router,
                    libraryService: libraryService,
                    playlistService: playlistService,
                    snackbar: snackbar,
                    playback: playback,
                    engine: engine,
                    lyricsService: lyricsService
                )
        }
        .sheet(item: $router.sheet) { destination in
            sheetView(for: destination)
                .presentationBackground(themeManager.palette.elevatedSurface)
                .withFullEnvironment(
                    themeManager: themeManager,
                    router: router,
                    libraryService: libraryService,
                    playlistService: playlistService,
                    snackbar: snackbar,
                    playback: playback,
                    engine: engine,
                    lyricsService: lyricsService
                )
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
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .bottom)
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
                    .foregroundColor(router.selectedTab == tab ? palette.primary : palette.textTertiary)
                Circle()
                    .fill(router.selectedTab == tab ? palette.primary : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        }
    }
}

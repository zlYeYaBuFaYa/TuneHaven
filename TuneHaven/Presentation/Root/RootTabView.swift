import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var snackbar: SnackbarState
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var engine: AudioEngine
    @Environment(\.themePalette) private var palette

    private var hasCustomBg: Bool {
        themeManager.currentStyle.hasCustomBackground || wallpaperManager.useCustomWallpaper
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
                .environment(\.themePalette, themeManager.palette)
                .environmentObject(themeManager)
                .environmentObject(router)
                .environmentObject(libraryService)
                .environmentObject(playlistService)
                .environmentObject(snackbar)
                .environmentObject(playback)
                .environmentObject(engine)
        }
        .sheet(item: $router.sheet) { destination in
            sheetView(for: destination)
                .environment(\.themePalette, themeManager.palette)
                .environmentObject(themeManager)
                .environmentObject(router)
                .environmentObject(libraryService)
                .environmentObject(playlistService)
                .environmentObject(snackbar)
                .environmentObject(playback)
                .environmentObject(engine)
        }
        .onAppear {
            AppLogger.shared.debug("[RootTabView] onAppear — palette.background=\(palette.background)")
        }
    }

    // MARK: - Custom Tab Bar

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(palette.separator)

            HStack(spacing: 0) {
                tabButton(.library, icon: "music.note.house", label: "音乐库")
                tabButton(.playlist, icon: "list.bullet.rectangle.portrait", label: "歌单")
                tabButton(.settings, icon: "gearshape", label: "设置")
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .background {
            if hasCustomBg {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .bottom)
            } else {
                palette.surface.ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func tabButton(_ tab: AppTab, icon: String, label: String) -> some View {
        Button {
            AppLogger.shared.debug("[RootTabView] tab switch: \(router.selectedTab) → \(tab)")
            router.selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .symbolVariant(router.selectedTab == tab ? .fill : .none)
                    .font(.system(size: 21))
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(router.selectedTab == tab ? palette.primary : palette.textSecondary)
            .animation(.easeInOut(duration: 0.15), value: router.selectedTab)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

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

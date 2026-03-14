import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.selectedTab) {
                LibraryTabView()
                    .tag(AppTab.library)
                    .tabItem { Label("音乐库", systemImage: "music.note.list") }

                PlaylistTabView()
                    .tag(AppTab.playlist)
                    .tabItem { Label("歌单", systemImage: "music.note.house") }

                SettingsTabView()
                    .tag(AppTab.settings)
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
            .accentColor(palette.primary)

            // Mini Player 固定在 TabBar 上方
            VStack(spacing: 0) {
                MiniPlayerBar()
                    .padding(.bottom, 4)
                Color.clear.frame(height: 0)
            }
        }
        .fullScreenCover(isPresented: .init(
            get:  { router.isPlayerPresented },
            set:  { router.isPlayerPresented = $0 }
        )) {
            PlayerView()
                .environment(\.themePalette, resolvedPalette)
                .environmentObject(router)
                .environmentObject(playlistService)
                .environmentObject(snackbar)
        }
        .sheet(item: $router.sheet) { destination in
            sheetView(for: destination)
                .environment(\.themePalette, resolvedPalette)
                .environmentObject(router)
                .environmentObject(playlistService)
                .environmentObject(snackbar)
        }
        // 每当 colorMode / theme 改变时重新计算色板
        .onChange(of: themeManager.colorMode) { _, _ in
            // SwiftUI 自动 re-render，palette 通过 resolvedPalette 传下去
        }
    }

    private var resolvedPalette: ThemeColorPalette {
        themeManager.resolvedPalette(for: colorScheme)
    }

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
        }
    }
}

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @EnvironmentObject private var libraryService: MusicLibraryService

    var body: some View {
        LibraryTabView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerBar()
            }
            .fullScreenCover(isPresented: .init(
                get:  { router.isPlayerPresented },
                set:  { router.isPlayerPresented = $0 }
            )) {
                PlayerView()
                    .environmentObject(themeManager)
                    .environmentObject(router)
                    .environmentObject(libraryService)
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
            .onChange(of: themeManager.colorMode) { _, _ in }
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
        case .batchAddSongs(let id):
            BatchAddSongsView(playlistId: id)
        }
    }
}

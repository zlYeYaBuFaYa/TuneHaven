import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette

    @StateObject private var groupService = PlaylistGroupService()

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            LibraryMainView()
                .fixNavigationControllerBackground(palette.background)
                .environmentObject(groupService)
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                        .environmentObject(groupService)
                        .environment(\.themePalette, palette)
                }
        }
        .background(palette.background.ignoresSafeArea())
        .toolbarBackground(palette.surface, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar()
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .artistDetail(let name):
            ArtistDetailView(artistName: name)
        case .albumDetail(let album, let artist):
            AlbumDetailView(albumName: album, artistName: artist)
        case .playlistDetail(let id):
            PlaylistDetailView(playlistId: id)
        case .songList(let title, let context):
            SongListView(title: title, context: context)
        case .importFiles:
            ImportFilesView()
        case .settings:
            SettingsView()
        case .songInfoEdit(let id):
            SongInfoEditView(songId: id)
        }
    }
}

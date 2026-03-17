import SwiftUI

struct PlaylistTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playlistService: PlaylistService
    @StateObject private var groupService = PlaylistGroupService()
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack(path: $router.playlistPath) {
            PlaylistMainView()
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
        case .playlistDetail(let id):
            PlaylistDetailView(playlistId: id)
        case .songList(let title, let context):
            SongListView(title: title, context: context)
        case .artistDetail(let name):
            ArtistDetailView(artistName: name)
        case .albumDetail(let album, let artist):
            AlbumDetailView(albumName: album, artistName: artist)
        case .songInfoEdit(let id):
            SongInfoEditView(songId: id)
        default:
            EmptyView()
        }
    }
}

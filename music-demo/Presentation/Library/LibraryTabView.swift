import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            LibraryMainView()
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                        .environment(\.themePalette, palette)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            router.present(.importFromFiles)
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(palette.primary)
                        }
                    }
                }
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

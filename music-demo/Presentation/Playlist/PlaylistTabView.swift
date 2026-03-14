import SwiftUI

struct PlaylistTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playlistService: PlaylistService
    @StateObject private var groupService = PlaylistGroupService()
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack(path: $router.playlistPath) {
            PlaylistMainView()
                .environmentObject(groupService)
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                        .environmentObject(groupService)
                        .environment(\.themePalette, palette)
                }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .playlistDetail(let id):
            PlaylistDetailView(playlistId: id)
        case .songList(let title, let context):
            SongListView(title: title, context: context)
        default:
            EmptyView()
        }
    }
}

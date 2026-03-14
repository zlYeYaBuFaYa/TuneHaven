import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            SettingsView()
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                        .environment(\.themePalette, palette)
                }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .songInfoEdit(let id):
            SongInfoEditView(songId: id)
        default:
            EmptyView()
        }
    }
}

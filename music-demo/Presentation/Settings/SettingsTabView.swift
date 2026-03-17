import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            SettingsView()
                .fixNavigationControllerBackground(palette.background)
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
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
        case .songInfoEdit(let id):
            SongInfoEditView(songId: id)
        default:
            EmptyView()
        }
    }
}

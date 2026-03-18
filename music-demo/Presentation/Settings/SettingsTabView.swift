import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @Environment(\.themePalette) private var palette

    var body: some View {
        let hasCustomBg = themeManager.currentStyle.hasCustomBackground || wallpaperManager.useCustomWallpaper
        NavigationStack(path: $router.settingsPath) {
            SettingsView()
                .themeContainerBackground()
                .fixNavigationControllerBackground(hasCustomBg ? Color.clear : palette.background)
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                        .themeContainerBackground()
                        .environment(\.themePalette, palette)
                }
        }
        .background(hasCustomBg ? Color.clear.ignoresSafeArea() : palette.background.ignoresSafeArea())
        .toolbarBackground(hasCustomBg ? Visibility.visible : .automatic, for: .navigationBar)
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

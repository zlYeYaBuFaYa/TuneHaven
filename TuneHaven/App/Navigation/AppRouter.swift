import SwiftUI

enum AppTab: Int, CaseIterable {
    case library = 0
    case playlist = 1
    case settings = 2
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var libraryPath  = NavigationPath()
    @Published var playlistPath = NavigationPath()
    @Published var settingsPath = NavigationPath()
    @Published var selectedTab: AppTab = .library
    @Published var sheet: SheetDestination?
    @Published var isPlayerPresented = false

    func navigate(to destination: AppDestination, in tab: AppTab? = nil) {
        let targetTab = tab ?? selectedTab
        selectedTab = targetTab
        switch targetTab {
        case .library:  libraryPath.append(destination)
        case .playlist: playlistPath.append(destination)
        case .settings: settingsPath.append(destination)
        }
    }

    func popToRoot(in tab: AppTab? = nil) {
        switch tab ?? selectedTab {
        case .library:  libraryPath  = NavigationPath()
        case .playlist: playlistPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }

    func present(_ sheet: SheetDestination) { self.sheet = sheet }
    func dismissSheet() { sheet = nil }

    func openPlayer() {
        isPlayerPresented = true
    }

    func closePlayer() {
        isPlayerPresented = false
    }
}

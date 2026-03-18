import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private let contentProvider = CarPlayContentProvider()

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        contentProvider.interfaceController = interfaceController
        print("[CarPlay] Connected")

        let tabBar = buildTabBar()
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        contentProvider.interfaceController = nil
        print("[CarPlay] Disconnected")
    }

    // MARK: - Tab Bar

    private func buildTabBar() -> CPTabBarTemplate {
        let tabs: [CPTemplate] = [
            contentProvider.makeNowPlayingTab(),
            contentProvider.makeSongsTab(),
            contentProvider.makeAlbumsTab(),
            contentProvider.makePlaylistsTab()
        ]
        let tabBar = CPTabBarTemplate(templates: tabs)
        tabBar.delegate = contentProvider
        return tabBar
    }
}

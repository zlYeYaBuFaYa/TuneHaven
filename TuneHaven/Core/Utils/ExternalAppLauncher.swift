import UIKit

@MainActor
enum ExternalAppLauncher {
    @discardableResult
    static func openBaiduNetdisk() -> Bool {
        guard let url = URL(string: "baidunetdisk://"),
              UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    static var isBaiduNetdiskInstalled: Bool {
        guard let url = URL(string: "baidunetdisk://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

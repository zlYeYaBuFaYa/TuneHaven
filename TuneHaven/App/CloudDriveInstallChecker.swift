import UIKit

enum CloudDriveInstallChecker {
    @MainActor
    static func isInstalled(_ provider: any CloudDriveProvider) -> Bool {
        guard let url = URL(string: "\(provider.urlScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

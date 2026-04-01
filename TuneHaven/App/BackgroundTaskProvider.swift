import UIKit

@MainActor
final class BackgroundTaskProvider: BackgroundTaskProviding {
    func beginTask(expirationHandler: (@Sendable () -> Void)?) -> UInt {
        UInt(UIApplication.shared.beginBackgroundTask(expirationHandler: expirationHandler).rawValue)
    }

    func endTask(_ identifier: UInt) {
        let taskId = UIBackgroundTaskIdentifier(rawValue: Int(identifier))
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
    }
}

import Foundation

@MainActor
protocol BackgroundTaskProviding {
    func beginTask(expirationHandler: (@Sendable () -> Void)?) -> UInt
    func endTask(_ identifier: UInt)
}

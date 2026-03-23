import Foundation

@MainActor
protocol AudioSessionManaging: AnyObject {
    @discardableResult func ensureActive() -> Bool
}

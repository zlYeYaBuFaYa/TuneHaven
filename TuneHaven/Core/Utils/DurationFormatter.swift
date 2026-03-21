import Foundation

enum DurationFormatter {
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

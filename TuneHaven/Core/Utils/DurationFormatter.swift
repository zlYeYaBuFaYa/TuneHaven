import Foundation

enum DurationFormatter {
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

extension TimeInterval {
    var formattedTime: String {
        DurationFormatter.format(self)
    }
}

extension DurationFormatter {
    /// 总时长的中文说法：「1 小时 12 分钟」「12 分钟」「不到 1 分钟」
    static func spoken(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 60 else { return "不到 1 分钟" }
        let totalMinutes = Int(seconds) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m) 分钟" }
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分钟"
    }
}

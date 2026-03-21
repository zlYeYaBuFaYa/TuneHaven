import Foundation

extension Date {
    private static let shortDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd"
        return fmt
    }()

    var relativeDescription: String {
        let interval = -timeIntervalSinceNow
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        if interval < 604800 { return "\(Int(interval / 86400))天前" }
        return Self.shortDateFormatter.string(from: self)
    }
}

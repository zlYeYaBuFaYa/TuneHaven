import Foundation

/// 对外链接。隐私政策页不由本仓库托管，提审前必须人工确认可访问。
enum AppURLs {
    /// 隐私政策。提审前须确认 https://tunehaven.app/privacy 已公开可打开。
    static let privacyPolicy = URL(string: "https://tunehaven.app/privacy")!

    /// Apple 订阅管理。用于付费墙与设置中的「管理订阅」。
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

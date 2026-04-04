import Foundation

/// 用户权限等级（Int rawValue 确保 Comparable 排序稳定，新增等级只需追加更大值）
enum SubscriptionTier: Int, Codable, Comparable, Sendable {
    case free = 0
    case premium = 1

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 用户订阅状态（用于 UI 展示）
enum SubscriptionStatus: Equatable, Sendable {
    case trial(daysRemaining: Int)
    case subscribed(expiresDate: Date)
    case lifetime
    case expired

    var isTrial: Bool {
        if case .trial = self { return true }
        return false
    }
}

/// 受控功能枚举 — 后期新增功能只需添加 case + 配置 requiredTier
enum PremiumFeature: String, CaseIterable, Sendable {
    case losslessPlayback
    case premiumTheme
    case webDAVImport
    case onlineLyricsSearch

    var requiredTier: SubscriptionTier {
        switch self {
        case .losslessPlayback, .premiumTheme, .webDAVImport, .onlineLyricsSearch:
            return .premium
        }
    }

    var displayName: String {
        switch self {
        case .losslessPlayback:   return "无损音质播放"
        case .premiumTheme:       return "高级主题风格"
        case .webDAVImport:       return "WebDAV 导入"
        case .onlineLyricsSearch: return "在线歌词搜索"
        }
    }
}

/// StoreKit 商品标识
enum SubscriptionProductID {
    static let yearlySubscription = "com.tunehaven.subscription.yearly"
    static let lifetimePurchase = "com.tunehaven.lifetime"
    static let allProductIDs: Set<String> = [yearlySubscription, lifetimePurchase]
    static let subscriptionGroupID = "tunehaven_premium"
}

import Foundation

/// 订阅数据访问协议 — 隔离 Domain 层对 StoreKit 的直接依赖
protocol SubscriptionProviding: Sendable {
    func fetchProducts() async throws -> [SubscriptionProduct]
    func purchase(_ productID: String) async throws -> PurchaseResult
    func restorePurchases() async throws
    /// 一次性解析当前全部权益状态（单次遍历 currentEntitlements）
    func resolveEntitlements() async -> EntitlementState
    /// 已校验的首次下载日期。可能需要联网，开发版上会等到失败才返回。
    func appOriginalPurchaseDate() async -> Date?
    /// 本机记录的首次启动日期，不联网。启动时用它先算出试用状态。
    func localInstallDate() -> Date?
    func transactionUpdates() -> AsyncStream<TransactionUpdate>
}

extension SubscriptionProviding {
    func localInstallDate() -> Date? { nil }
}

/// 权益解析结果
struct EntitlementState: Sendable {
    let hasLifetime: Bool
    let hasActiveSubscription: Bool
    let subscriptionExpirationDate: Date?
}

/// 商品信息（跨层传递用）
struct SubscriptionProduct: Identifiable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
    let description: String
    let type: ProductType

    enum ProductType: Sendable {
        case autoRenewable
        case nonConsumable
    }
}

/// 购买结果
enum PurchaseResult: Sendable {
    case success
    case pending
    case cancelled
}

/// 交易更新事件
enum TransactionUpdate: Sendable {
    case purchased
    case revoked
}

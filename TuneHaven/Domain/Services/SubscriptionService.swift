import Foundation
import Combine

@MainActor
final class SubscriptionService: ObservableObject {
    private let log = AppLogger.shared
    private let provider: SubscriptionProviding

    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var status: SubscriptionStatus = .expired
    @Published private(set) var products: [SubscriptionProduct] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var restoreError: String?

    static let trialDurationDays = 30
    private var transactionTask: Task<Void, Never>?

    init(provider: SubscriptionProviding) {
        self.provider = provider
    }

    // MARK: - Initialization

    /// 启动用：只读上次缓存的权益和本地首次启动日期，不访问 StoreKit，立即返回。
    /// 之后再调用 `initialize()` 在后台读取购买记录并联网校验，状态变化经 `$tier` 通知。
    func loadLocalStatus() {
        let cached = provider.cachedEntitlements()
            ?? EntitlementState(hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        apply(cached, installDate: provider.localInstallDate())
    }

    func initialize() async {
        await refreshStatus()
        await loadProducts()
        startListeningForUpdates()
    }

    // MARK: - Access Control

    func canAccess(_ feature: PremiumFeature) -> Bool {
        tier >= feature.requiredTier
    }

    // MARK: - Status

    func refreshStatus() async {
        let entitlements = await provider.resolveEntitlements()
        if entitlements.hasLifetime || entitlements.hasActiveSubscription {
            apply(entitlements, installDate: nil)
        } else {
            apply(entitlements, installDate: await provider.appOriginalPurchaseDate())
        }
    }

    /// 权益优先级：终身买断 > 有效订阅 > 试用期 > Free
    private func apply(_ entitlements: EntitlementState, installDate: Date?) {
        if entitlements.hasLifetime {
            tier = .premium
            status = .lifetime
            log.info("[Subscription] 状态: 终身买断")
            return
        }

        if entitlements.hasActiveSubscription {
            tier = .premium
            status = .subscribed(expiresDate: entitlements.subscriptionExpirationDate ?? Date.distantFuture)
            log.info("[Subscription] 状态: 年度订阅有效")
            return
        }

        if let installDate {
            let daysSinceInstall = Calendar.current.dateComponents(
                [.day], from: installDate, to: Date()
            ).day ?? Int.max

            if daysSinceInstall < Self.trialDurationDays {
                let remaining = Self.trialDurationDays - daysSinceInstall
                tier = .premium
                status = .trial(daysRemaining: remaining)
                log.info("[Subscription] 状态: 试用期 剩余\(remaining)天")
                return
            }
        }

        tier = .free
        status = .expired
        log.info("[Subscription] 状态: Free 用户")
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            products = try await provider.fetchProducts()
            log.debug("[Subscription] 加载商品: \(products.count) 个")
        } catch {
            log.error("[Subscription] 商品加载失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: SubscriptionProduct) async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await provider.purchase(product.id)
        switch result {
        case .success:
            await refreshStatus()
            log.info("[Subscription] 购买成功: \(product.id)")
        case .pending:
            log.info("[Subscription] 购买等待审批: \(product.id)")
        case .cancelled:
            log.info("[Subscription] 用户取消购买: \(product.id)")
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        restoreError = nil
        do {
            try await provider.restorePurchases()
            await refreshStatus()
            log.info("[Subscription] 恢复购买完成")
        } catch {
            restoreError = "恢复购买失败，请检查网络后重试"
            log.error("[Subscription] 恢复购买失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Transaction Listener

    private func startListeningForUpdates() {
        transactionTask?.cancel()
        transactionTask = Task { [weak self] in
            guard let self else { return }
            for await update in self.provider.transactionUpdates() {
                self.log.debug("[Subscription] 收到交易更新: \(update)")
                await self.refreshStatus()
            }
        }
    }
}

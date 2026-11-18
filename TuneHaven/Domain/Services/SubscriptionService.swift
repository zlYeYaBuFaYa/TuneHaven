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
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productLoadError: String?
    @Published private(set) var pendingProductID: String?
    @Published private(set) var restoreError: String?
    /// `tier` 是否已由 StoreKit 确认。`loadLocalStatus()` 给出的只是本地推断，可能是临时 Free，
    /// 依据权益做不可逆的操作时要等它为 true。
    @Published private(set) var isStatusVerified = false

    static let trialDurationDays = 30
    private var transactionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var appliedRefreshGeneration = 0

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

    /// 启动和回前台可能同时触发，正在刷新时直接等那一次的结果。
    func refreshStatus() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// 购买、恢复和交易更新之后要读最新状态，不能复用之前发起的刷新。
    /// 并发时只采用最后发起的那次结果，先发起的晚返回也不会覆盖。
    private func performRefresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let entitlements = await provider.resolveEntitlements()
        let installDate = entitlements.hasLifetime || entitlements.hasActiveSubscription
            ? nil
            : await provider.appOriginalPurchaseDate()
        guard generation > appliedRefreshGeneration else { return }
        appliedRefreshGeneration = generation
        apply(entitlements, installDate: installDate)
        isStatusVerified = true
    }

    /// 权益优先级：终身买断 > 有效订阅 > 试用期 > Free
    private func apply(_ entitlements: EntitlementState, installDate: Date?) {
        if entitlements.hasLifetime {
            pendingProductID = nil
            tier = .premium
            status = .lifetime
            log.info("[Subscription] 状态: 终身买断")
            return
        }

        if entitlements.hasActiveSubscription {
            pendingProductID = nil
            tier = .premium
            status = .subscribed(expiresDate: entitlements.subscriptionExpirationDate ?? Date.distantFuture)
            log.info("[Subscription] 状态: 年度订阅有效")
            return
        }

        if let installDate {
            let daysSinceInstall = Calendar.current.dateComponents(
                [.day], from: installDate, to: Date()
            ).day ?? Int.max

            // 负数说明系统时间被调到首次启动之前，按试用结束处理
            if (0..<Self.trialDurationDays).contains(daysSinceInstall) {
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
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        productLoadError = nil
        defer { isLoadingProducts = false }
        do {
            products = try await provider.fetchProducts()
            log.debug("[Subscription] 加载商品: \(products.count) 个")
        } catch {
            productLoadError = "暂时无法获取购买方案，请检查网络后重试"
            log.error("[Subscription] 商品加载失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ product: SubscriptionProduct) async throws -> PurchaseResult {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await provider.purchase(product.id)
        switch result {
        case .success:
            await performRefresh()
            log.info("[Subscription] 购买成功: \(product.id)")
        case .pending:
            pendingProductID = product.id
            log.info("[Subscription] 购买等待审批: \(product.id)")
        case .cancelled:
            log.info("[Subscription] 用户取消购买: \(product.id)")
        }
        return result
    }

    // MARK: - Restore

    func restorePurchases() async {
        restoreError = nil
        do {
            try await provider.restorePurchases()
            await performRefresh()
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
                await self.performRefresh()
            }
        }
    }
}

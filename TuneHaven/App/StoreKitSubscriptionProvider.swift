import StoreKit
import Foundation

final class StoreKitSubscriptionProvider: SubscriptionProviding {
    private let log = AppLogger.shared

    // MARK: - Products

    func fetchProducts() async throws -> [SubscriptionProduct] {
        let storeProducts = try await Product.products(
            for: SubscriptionProductID.allProductIDs
        )
        return storeProducts.map { product in
            SubscriptionProduct(
                id: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                description: product.description,
                type: product.type == .autoRenewable ? .autoRenewable : .nonConsumable
            )
        }
    }

    // MARK: - Purchase

    func purchase(_ productID: String) async throws -> PurchaseResult {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw AppError.purchaseFailed("商品不存在")
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw AppError.purchaseFailed("购买过程出错，请稍后重试")
        }
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            return .success
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()
    }

    // MARK: - Entitlements

    func resolveEntitlements() async -> EntitlementState {
        var hasLifetime = false
        var hasActiveSubscription = false
        var subscriptionExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  transaction.revocationDate == nil else { continue }

            if transaction.productID == SubscriptionProductID.lifetimePurchase {
                hasLifetime = true
            } else if transaction.productID == SubscriptionProductID.yearlySubscription {
                hasActiveSubscription = true
                subscriptionExpirationDate = transaction.expirationDate
            }
        }

        let state = EntitlementState(
            hasLifetime: hasLifetime,
            hasActiveSubscription: hasActiveSubscription,
            subscriptionExpirationDate: subscriptionExpirationDate
        )
        saveCachedEntitlements(state)
        return state
    }

    func cachedEntitlements() -> EntitlementState? {
        guard let dict = UserDefaults.standard.dictionary(forKey: AppStorageKey.cachedEntitlements) else { return nil }
        let expiration = dict["expiration"] as? Date
        let subscriptionValid = (dict["subscription"] as? Bool ?? false) && (expiration.map { $0 > Date() } ?? true)
        return EntitlementState(
            hasLifetime: dict["lifetime"] as? Bool ?? false,
            hasActiveSubscription: subscriptionValid,
            subscriptionExpirationDate: expiration
        )
    }

    private func saveCachedEntitlements(_ state: EntitlementState) {
        var dict: [String: Any] = [
            "lifetime": state.hasLifetime,
            "subscription": state.hasActiveSubscription,
        ]
        if let expiration = state.subscriptionExpirationDate { dict["expiration"] = expiration }
        UserDefaults.standard.set(dict, forKey: AppStorageKey.cachedEntitlements)
    }

    // MARK: - Trial

    func localInstallDate() -> Date? {
        FirstLaunchDateStore.live.earliestDate()
    }

    /// 已校验的首次下载日期不会变，取到一次后缓存，之后不再请求 AppTransaction。
    func appOriginalPurchaseDate() async -> Date? {
        if let cached = UserDefaults.standard.object(forKey: AppStorageKey.verifiedOriginalPurchaseDate) as? Date {
            return cached
        }
        do {
            let appTransaction = try await AppTransaction.shared
            switch appTransaction {
            case .verified(let transaction):
                UserDefaults.standard.set(transaction.originalPurchaseDate, forKey: AppStorageKey.verifiedOriginalPurchaseDate)
                return transaction.originalPurchaseDate
            case .unverified:
                return FirstLaunchDateStore.live.earliestDate()
            }
        } catch {
            log.error("[StoreKit] AppTransaction 获取失败: \(error)")
            return FirstLaunchDateStore.live.earliestDate()
        }
    }

    // MARK: - Transaction Updates

    func transactionUpdates() -> AsyncStream<TransactionUpdate> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard let transaction = try? self.checkVerified(result) else { continue }
                    await transaction.finish()

                    if transaction.revocationDate != nil {
                        continuation.yield(.revoked)
                    } else {
                        continuation.yield(.purchased)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }
}

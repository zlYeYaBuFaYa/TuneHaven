import Testing
@testable import TuneHaven

@Suite("购买审批反馈")
@MainActor
struct SubscriptionPurchaseFeedbackTests {
    private var product: SubscriptionProduct {
        SubscriptionProduct(id: SubscriptionProductID.yearlySubscription, displayName: "年度订阅",
                            displayPrice: "测试价格", description: "", type: .autoRenewable)
    }

    @Test("等待审批保留状态，不授予 Premium")
    func pendingDoesNotUnlock() async throws {
        let provider = MockSubscriptionProvider()
        provider.purchaseResult = .pending
        let service = SubscriptionService(provider: provider)
        let result = try await service.purchase(product)
        guard case .pending = result else { Issue.record("必须向 UI 传回 pending"); return }
        #expect(service.pendingProductID == product.id)
        #expect(service.tier == .free)
        #expect(!service.isPurchasing)
    }

    @Test("批准后刷新权益，清除待审批提示")
    func approvalClearsPending() async throws {
        let provider = MockSubscriptionProvider()
        provider.purchaseResult = .pending
        let service = SubscriptionService(provider: provider)
        try await service.purchase(product)
        provider.entitlementState = EntitlementState(hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        await service.refreshStatus()
        #expect(service.pendingProductID == nil)
        #expect(service.status == .lifetime)
    }

    @Test("用户取消不是成功，也不是待审批")
    func cancellationStaysCancelled() async throws {
        let provider = MockSubscriptionProvider()
        provider.purchaseResult = .cancelled
        let service = SubscriptionService(provider: provider)
        let result = try await service.purchase(product)
        guard case .cancelled = result else { Issue.record("必须保留取消结果"); return }
        #expect(service.pendingProductID == nil)
        #expect(!service.isPurchasing)
    }
}

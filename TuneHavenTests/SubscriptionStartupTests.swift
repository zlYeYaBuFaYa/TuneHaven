import Testing
import Foundation
@testable import TuneHaven

@Suite("订阅启动：先本地后联网")
@MainActor
struct SubscriptionStartupTests {

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    @Test("loadLocalStatus 只用缓存和本地首次启动日期，不读 AppTransaction")
    func localStatusUsesLocalInstallDate() async {
        let provider = MockSubscriptionProvider()
        provider.localFirstLaunchDate = daysAgo(3)
        provider.originalPurchaseDate = daysAgo(60)
        let service = SubscriptionService(provider: provider)

        service.loadLocalStatus()

        #expect(service.tier == .premium)
        #expect(service.status == .trial(daysRemaining: 27))
    }

    @Test("联网校验后以 AppTransaction 为准，可能从试用降为 Free")
    func networkRefreshOverridesLocalStatus() async {
        let provider = MockSubscriptionProvider()
        provider.localFirstLaunchDate = daysAgo(3)
        provider.originalPurchaseDate = daysAgo(60)
        let service = SubscriptionService(provider: provider)

        service.loadLocalStatus()
        await service.initialize()

        #expect(service.tier == .free)
        #expect(service.status == .expired)
    }

    @Test("缓存里有买断记录时，启动即为终身买断，不等 StoreKit")
    func lifetimeIsResolvedFromCache() async {
        let provider = MockSubscriptionProvider()
        provider.cachedEntitlementState = EntitlementState(hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        let service = SubscriptionService(provider: provider)

        service.loadLocalStatus()

        #expect(service.tier == .premium)
        #expect(service.status == .lifetime)
    }

    @Test("启动不读实时购买记录：缓存为空时即使已买断也先按本地日期算，后台刷新后变为买断")
    func liveEntitlementsAppliedAfterRefresh() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        let service = SubscriptionService(provider: provider)

        service.loadLocalStatus()
        #expect(service.tier == .free)

        await service.initialize()
        #expect(service.status == .lifetime)
    }

    @Test("没有本地日期时启动先视为 Free，不阻塞")
    func missingLocalDateIsFree() async {
        let provider = MockSubscriptionProvider()
        let service = SubscriptionService(provider: provider)

        service.loadLocalStatus()

        #expect(service.tier == .free)
    }
}

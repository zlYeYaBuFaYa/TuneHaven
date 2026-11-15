import Testing
import Foundation
@testable import TuneHaven

@Suite("订阅启动：先本地后联网")
@MainActor
struct SubscriptionStartupTests {

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    @Test("loadLocalStatus 只用本地首次启动日期，不读 AppTransaction")
    func localStatusUsesLocalInstallDate() async {
        let provider = MockSubscriptionProvider()
        provider.localFirstLaunchDate = daysAgo(3)
        provider.originalPurchaseDate = daysAgo(60)
        let service = SubscriptionService(provider: provider)

        await service.loadLocalStatus()

        #expect(service.tier == .premium)
        #expect(service.status == .trial(daysRemaining: 27))
    }

    @Test("联网校验后以 AppTransaction 为准，可能从试用降为 Free")
    func networkRefreshOverridesLocalStatus() async {
        let provider = MockSubscriptionProvider()
        provider.localFirstLaunchDate = daysAgo(3)
        provider.originalPurchaseDate = daysAgo(60)
        let service = SubscriptionService(provider: provider)

        await service.loadLocalStatus()
        await service.initialize()

        #expect(service.tier == .free)
        #expect(service.status == .expired)
    }

    @Test("本地已有买断记录时，启动即为终身买断")
    func lifetimeIsResolvedLocally() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        let service = SubscriptionService(provider: provider)

        await service.loadLocalStatus()

        #expect(service.tier == .premium)
        #expect(service.status == .lifetime)
    }

    @Test("没有本地日期时启动先视为 Free，不阻塞")
    func missingLocalDateIsFree() async {
        let provider = MockSubscriptionProvider()
        let service = SubscriptionService(provider: provider)

        await service.loadLocalStatus()

        #expect(service.tier == .free)
    }
}

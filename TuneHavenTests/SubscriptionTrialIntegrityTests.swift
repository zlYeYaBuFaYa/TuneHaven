import Testing
import Foundation
@testable import TuneHaven

@Suite("试用期防重置：Keychain 首次启动日期")
struct FirstLaunchDateStoreTests {

    private final class FakeKeychain: @unchecked Sendable {
        var data: Data?
    }

    private func makeStore(keychain: FakeKeychain) -> (FirstLaunchDateStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "FirstLaunchDateStoreTests-\(UUID().uuidString)")!
        let store = FirstLaunchDateStore(
            defaults: defaults,
            loadKeychain: { keychain.data },
            saveKeychain: { keychain.data = $0 }
        )
        return (store, defaults)
    }

    private func keychainData(_ date: Date) -> Data {
        Data(String(date.timeIntervalSince1970).utf8)
    }

    @Test("首次启动时两边都写入当前时间")
    func recordsNowWhenEmpty() {
        let keychain = FakeKeychain()
        let (store, defaults) = makeStore(keychain: keychain)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        store.recordIfNeeded(now: now)

        #expect(store.earliestDate() == now)
        #expect(defaults.object(forKey: AppStorageKey.appFirstLaunchDate) as? Date == now)
        #expect(keychain.data == keychainData(now))
    }

    @Test("重装后 UserDefaults 为空，从 Keychain 恢复原日期")
    func restoresFromKeychainAfterReinstall() {
        let keychain = FakeKeychain()
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        keychain.data = keychainData(original)
        let (store, defaults) = makeStore(keychain: keychain)

        store.recordIfNeeded(now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(store.earliestDate() == original)
        #expect(defaults.object(forKey: AppStorageKey.appFirstLaunchDate) as? Date == original)
    }

    @Test("两边不一致时取较早值并同步")
    func keepsEarlierDate() {
        let keychain = FakeKeychain()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_750_000_000)
        keychain.data = keychainData(later)
        let (store, defaults) = makeStore(keychain: keychain)
        defaults.set(earlier, forKey: AppStorageKey.appFirstLaunchDate)

        store.recordIfNeeded()

        #expect(store.earliestDate() == earlier)
        #expect(keychain.data == keychainData(earlier))
    }
}

@Suite("订阅刷新：负天数、在途去重与结果顺序")
@MainActor
struct SubscriptionRefreshTests {

    private func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date())!
    }

    @Test("首次启动日期在未来（系统时间被调早）按试用结束处理")
    func futureInstallDateIsExpired() async {
        let provider = MockSubscriptionProvider()
        provider.originalPurchaseDate = daysFromNow(5)
        let service = SubscriptionService(provider: provider)

        await service.refreshStatus()

        #expect(service.tier == .free)
        #expect(service.status == .expired)
    }

    @Test("同时触发两次刷新只请求一次")
    func concurrentRefreshesShareOneRequest() async {
        let provider = ScriptedProvider(responses: [
            .init(delay: .milliseconds(50), state: .none)
        ])
        let service = SubscriptionService(provider: provider)

        async let first: Void = service.refreshStatus()
        async let second: Void = service.refreshStatus()
        _ = await (first, second)

        #expect(provider.resolveCount == 1)
        #expect(provider.purchaseDateCount == 1)
        #expect(service.isStatusVerified)
    }

    @Test("先发起的慢刷新晚返回，不覆盖购买后的新状态")
    func staleRefreshDoesNotOverwritePurchase() async throws {
        let provider = ScriptedProvider(responses: [
            .init(delay: .milliseconds(150), state: .none),
            .init(delay: .zero, state: .lifetime)
        ])
        let service = SubscriptionService(provider: provider)

        let slow = Task { await service.refreshStatus() }
        while provider.resolveCount == 0 { await Task.yield() }
        try await service.purchase(SubscriptionProduct(id: "lifetime", displayName: "", displayPrice: "", description: "", type: .nonConsumable))
        #expect(service.status == .lifetime)

        await slow.value
        #expect(service.status == .lifetime)
        #expect(service.tier == .premium)
    }
}

private final class ScriptedProvider: SubscriptionProviding, @unchecked Sendable {
    struct Response {
        enum State { case none, lifetime }
        let delay: Duration
        let state: State
    }

    private var responses: [Response]
    private(set) var resolveCount = 0
    private(set) var purchaseDateCount = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func fetchProducts() async throws -> [SubscriptionProduct] { [] }
    func purchase(_ productID: String) async throws -> PurchaseResult { .success }
    func restorePurchases() async throws {}

    func resolveEntitlements() async -> EntitlementState {
        resolveCount += 1
        let response = responses.isEmpty ? Response(delay: .zero, state: .none) : responses.removeFirst()
        try? await Task.sleep(for: response.delay)
        return EntitlementState(
            hasLifetime: response.state == .lifetime,
            hasActiveSubscription: false,
            subscriptionExpirationDate: nil
        )
    }

    func appOriginalPurchaseDate() async -> Date? {
        purchaseDateCount += 1
        return nil
    }

    func transactionUpdates() -> AsyncStream<TransactionUpdate> {
        AsyncStream { $0.finish() }
    }
}

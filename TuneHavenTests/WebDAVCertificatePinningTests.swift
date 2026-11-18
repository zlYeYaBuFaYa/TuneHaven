import Foundation
import Testing
@testable import TuneHaven

@Suite("WebDAV 自签证书：首次信任后固定指纹")
struct WebDAVTrustPolicyTests {
    @Test("未开启信任自签或系统已信任时走默认校验")
    func defaultHandlingCases() {
        let off = WebDAVTrustPolicy(trustSelfSigned: false, pinnedFingerprint: "aa")
        #expect(off.decide(systemTrusted: false, presented: "bb") == .defaultHandling)
        let on = WebDAVTrustPolicy(trustSelfSigned: true, pinnedFingerprint: "aa")
        #expect(on.decide(systemTrusted: true, presented: "bb") == .defaultHandling)
        #expect(on.decide(systemTrusted: false, presented: nil) == .defaultHandling)
    }

    @Test("首次连接记住指纹，之后同一张证书接受，换证书拒绝")
    func pinThenMatchOrReject() {
        let first = WebDAVTrustPolicy(trustSelfSigned: true)
        #expect(first.decide(systemTrusted: false, presented: "aa") == .acceptAndPin("aa"))
        let pinned = WebDAVTrustPolicy(trustSelfSigned: true, pinnedFingerprint: "aa")
        #expect(pinned.decide(systemTrusted: false, presented: "aa") == .accept)
        #expect(pinned.decide(systemTrusted: false, presented: "bb") == .rejectChanged)
    }

    @Test("指纹是证书 DER 的 SHA-256 小写十六进制")
    func fingerprintFormat() {
        let fingerprint = WebDAVSessionDelegate.fingerprint(of: Data("abc".utf8))
        #expect(fingerprint == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@MainActor
@Suite("WebDAV 账户：证书指纹的保存与清除")
struct WebDAVCertificatePinStorageTests {
    private func makeService(store: MemoryAccountStore, factory: CapturingFactory) async -> WebDAVService {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        let subscription = SubscriptionService(provider: provider)
        await subscription.refreshStatus()
        return WebDAVService(accountStore: store, clientFactory: factory, importService: NoopImporter(),
                             fileStorage: MockFileStorageProviding(), subscriptionService: subscription)
    }

    @Test("首次连接回调的指纹存入账户，下次连接带上它")
    func connectPersistsAndReusesPin() async throws {
        let store = MemoryAccountStore()
        let account = WebDAVAccount(serverURL: "https://nas.local/dav", username: "u", trustSelfSignedCert: true)
        try store.saveAccount(account, password: "p")
        let factory = CapturingFactory()
        let service = await makeService(store: store, factory: factory)
        service.loadAccounts()

        try await service.connect(to: account)
        #expect(factory.policies.last?.pinnedFingerprint == nil)
        factory.policies.last?.onPinned?("aa")
        await waitUntil { store.accounts.first?.pinnedCertificateSHA256 == "aa" }
        #expect(store.accounts.first?.pinnedCertificateSHA256 == "aa")

        try await service.connect(to: account)
        #expect(factory.policies.last?.pinnedFingerprint == "aa")
    }

    @Test("重新保存账户清空指纹，测试连接不记住证书")
    func resaveClearsPin() async throws {
        let store = MemoryAccountStore()
        var account = WebDAVAccount(serverURL: "https://nas.local/dav", username: "u", trustSelfSignedCert: true)
        account.pinnedCertificateSHA256 = "aa"
        try store.saveAccount(account, password: "p")
        let factory = CapturingFactory()
        let service = await makeService(store: store, factory: factory)

        try service.updateAccount(account, password: nil)
        #expect(store.accounts.first?.pinnedCertificateSHA256 == nil)

        _ = try await service.testConnection(account: account, password: "p")
        #expect(factory.policies.last?.onPinned == nil)
        #expect(factory.policies.last?.pinnedFingerprint == nil)
    }

    @Test("旧版本保存的账户没有指纹字段也能读取")
    func decodesLegacyAccount() throws {
        let legacy = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","displayName":"","serverURL":"https://a","username":"u","trustSelfSignedCert":true,"createdAt":0}"#
        let account = try JSONDecoder().decode(WebDAVAccount.self, from: Data(legacy.utf8))
        #expect(account.pinnedCertificateSHA256 == nil)
    }
}

private final class MemoryAccountStore: WebDAVAccountStoring {
    private(set) var accounts: [WebDAVAccount] = []
    private var passwords: [UUID: String] = [:]
    func loadAccounts() -> [WebDAVAccount] { accounts }
    func saveAccount(_ account: WebDAVAccount, password: String?) throws {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        if let password { passwords[account.id] = password }
    }
    func deleteAccount(id: UUID) throws { accounts.removeAll { $0.id == id } }
    func password(for accountId: UUID) -> String? { passwords[accountId] }
    func updateLastConnected(accountId: UUID) throws {}
}

private final class CapturingFactory: WebDAVClientFactory {
    private(set) var policies: [WebDAVTrustPolicy] = []
    func makeClient(baseURL: URL, username: String, password: String, trust: WebDAVTrustPolicy) -> WebDAVClientProtocol {
        policies.append(trust)
        return EmptyClient()
    }
}

private final class EmptyClient: WebDAVClientProtocol {
    func testConnection() async throws -> Bool { true }
    func listDirectory(path: String) async throws -> [WebDAVFile] { [] }
    func downloadFile(remotePath: String, to destination: URL,
                      progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL { destination }
    func cancelDownload() async {}
}

@MainActor
private final class NoopImporter: FileImporting {
    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
        ImportResult(successCount: 0, skippedDuplicateCount: 0, skippedFormatCount: 0,
                     failedCount: 0, incompleteMetadataCount: 0, skippedOversizeCount: 0, details: [])
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

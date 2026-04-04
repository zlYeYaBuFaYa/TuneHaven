import Testing
import Foundation
@testable import TuneHaven

// MARK: - SubscriptionTier Tests

@Suite("SubscriptionTier Tests")
struct SubscriptionTierTests {

    @Test("Comparable: free < premium")
    func testComparable() {
        #expect(SubscriptionTier.free < SubscriptionTier.premium)
        #expect(!(SubscriptionTier.premium < SubscriptionTier.free))
    }

    @Test("free rawValue = 0, premium rawValue = 1")
    func testRawValues() {
        #expect(SubscriptionTier.free.rawValue == 0)
        #expect(SubscriptionTier.premium.rawValue == 1)
    }

    @Test("Codable 编解码正确")
    func testCodable() throws {
        let data = try JSONEncoder().encode(SubscriptionTier.premium)
        let decoded = try JSONDecoder().decode(SubscriptionTier.self, from: data)
        #expect(decoded == .premium)
    }
}

// MARK: - SubscriptionStatus Tests

@Suite("SubscriptionStatus Tests")
struct SubscriptionStatusTests {

    @Test("trial isTrial 返回 true")
    func testIsTrial() {
        let status = SubscriptionStatus.trial(daysRemaining: 15)
        #expect(status.isTrial == true)
    }

    @Test("subscribed isTrial 返回 false")
    func testSubscribedNotTrial() {
        let status = SubscriptionStatus.subscribed(expiresDate: Date())
        #expect(status.isTrial == false)
    }

    @Test("lifetime isTrial 返回 false")
    func testLifetimeNotTrial() {
        #expect(SubscriptionStatus.lifetime.isTrial == false)
    }

    @Test("expired isTrial 返回 false")
    func testExpiredNotTrial() {
        #expect(SubscriptionStatus.expired.isTrial == false)
    }

    @Test("Equatable: 相同 case 和值相等")
    func testEquatable() {
        let date = Date()
        #expect(SubscriptionStatus.subscribed(expiresDate: date) == .subscribed(expiresDate: date))
        #expect(SubscriptionStatus.lifetime == .lifetime)
        #expect(SubscriptionStatus.expired == .expired)
        #expect(SubscriptionStatus.trial(daysRemaining: 5) == .trial(daysRemaining: 5))
    }

    @Test("Equatable: 不同 case 不相等")
    func testNotEqual() {
        #expect(SubscriptionStatus.lifetime != .expired)
        #expect(SubscriptionStatus.trial(daysRemaining: 5) != .trial(daysRemaining: 10))
    }
}

// MARK: - PremiumFeature Tests

@Suite("PremiumFeature Tests")
struct PremiumFeatureTests {

    @Test("所有功能 requiredTier 为 premium")
    func testAllRequirePremium() {
        for feature in PremiumFeature.allCases {
            #expect(feature.requiredTier == .premium)
        }
    }

    @Test("displayName 非空")
    func testDisplayNames() {
        for feature in PremiumFeature.allCases {
            #expect(!feature.displayName.isEmpty)
        }
    }

    @Test("allCases 包含 4 个功能")
    func testCaseCount() {
        #expect(PremiumFeature.allCases.count == 4)
    }

    @Test("rawValue 可作为 String 传递")
    func testRawValues() {
        #expect(PremiumFeature.losslessPlayback.rawValue == "losslessPlayback")
        #expect(PremiumFeature.premiumTheme.rawValue == "premiumTheme")
        #expect(PremiumFeature.webDAVImport.rawValue == "webDAVImport")
        #expect(PremiumFeature.onlineLyricsSearch.rawValue == "onlineLyricsSearch")
    }
}

// MARK: - Song.isLossless Tests

@Suite("Song.isLossless Tests")
struct SongIsLosslessTests {

    @Test("MP3 不是无损")
    func testMP3NotLossless() {
        let song = makeSongWithFormat("mp3")
        #expect(song.isLossless == false)
    }

    @Test("FLAC 是无损")
    func testFLACIsLossless() {
        let song = makeSongWithFormat("flac")
        #expect(song.isLossless == true)
    }

    @Test("WAV 是无损")
    func testWAVIsLossless() {
        let song = makeSongWithFormat("wav")
        #expect(song.isLossless == true)
    }

    @Test("AIFF 是无损")
    func testAIFFIsLossless() {
        let song = makeSongWithFormat("aiff")
        #expect(song.isLossless == true)
    }

    @Test("AIF 是无损")
    func testAIFIsLossless() {
        let song = makeSongWithFormat("aif")
        #expect(song.isLossless == true)
    }

    @Test("CAF 是无损")
    func testCAFIsLossless() {
        let song = makeSongWithFormat("caf")
        #expect(song.isLossless == true)
    }

    @Test("ALAC 格式标识是无损")
    func testALACFormatIsLossless() {
        let song = makeSongWithFormat("alac")
        #expect(song.isLossless == true)
    }

    @Test("M4A 带 ALAC 编码器是无损")
    func testM4AWithALACEncoder() {
        let song = makeSongWithFormat("m4a", encoder: "Apple Lossless Audio Codec")
        #expect(song.isLossless == true)
    }

    @Test("M4A 带 AAC 编码器不是无损")
    func testM4AWithAACEncoder() {
        let song = makeSongWithFormat("m4a", encoder: "AAC")
        #expect(song.isLossless == false)
    }

    @Test("M4A 无编码器高比特率是无损")
    func testM4AHighBitRate() {
        let song = makeSongWithFormat("m4a", bitRate: 700)
        #expect(song.isLossless == true)
    }

    @Test("M4A 无编码器低比特率不是无损")
    func testM4ALowBitRate() {
        let song = makeSongWithFormat("m4a", bitRate: 256)
        #expect(song.isLossless == false)
    }

    @Test("M4A 无编码器无比特率不是无损")
    func testM4ANoInfo() {
        let song = makeSongWithFormat("m4a")
        #expect(song.isLossless == false)
    }

    @Test("AAC 不是无损")
    func testAACNotLossless() {
        let song = makeSongWithFormat("aac")
        #expect(song.isLossless == false)
    }

    @Test("格式名大小写不敏感")
    func testCaseInsensitive() {
        let song = makeSongWithFormat("FLAC")
        #expect(song.isLossless == true)
    }

    private func makeSongWithFormat(_ format: String, encoder: String? = nil, bitRate: Int? = nil) -> Song {
        Song(
            id: UUID(),
            title: "Test",
            artist: "Artist",
            album: "Album",
            duration: 180,
            fileHash: UUID().uuidString,
            fileRelativePath: "test.\(format)",
            coverImagePath: nil,
            lyricsPath: nil,
            lyricsSource: nil,
            metadata: Metadata(
                format: format,
                sampleRate: 44100,
                bitRate: bitRate,
                channels: 2,
                encoder: encoder,
                trackNumber: nil,
                year: nil,
                genre: nil
            ),
            importDate: Date(),
            fileSize: 1024,
            playCount: 0,
            isFavorite: false,
            favoriteDate: nil,
            lastPlayedDate: nil
        )
    }
}

// MARK: - SubscriptionService Tests

@Suite("SubscriptionService Tests")
@MainActor
struct SubscriptionServiceTests {

    // MARK: - canAccess

    @Test("Premium 用户可访问所有功能")
    func testPremiumCanAccessAll() async {
        let service = await makeService(tier: .premium)
        for feature in PremiumFeature.allCases {
            #expect(service.canAccess(feature) == true)
        }
    }

    @Test("Free 用户不能访问任何 Premium 功能")
    func testFreeCannotAccess() async {
        let service = await makeService(tier: .free)
        for feature in PremiumFeature.allCases {
            #expect(service.canAccess(feature) == false)
        }
    }

    // MARK: - refreshStatus: Lifetime

    @Test("终身买断 → tier=premium, status=lifetime")
    func testLifetimeStatus() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: true,
            hasActiveSubscription: false,
            subscriptionExpirationDate: nil
        )
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()

        #expect(service.tier == .premium)
        #expect(service.status == .lifetime)
    }

    // MARK: - refreshStatus: Active Subscription

    @Test("有效订阅 → tier=premium, status=subscribed")
    func testActiveSubscription() async {
        let expiresDate = Date().addingTimeInterval(30 * 24 * 3600)
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: false,
            hasActiveSubscription: true,
            subscriptionExpirationDate: expiresDate
        )
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()

        #expect(service.tier == .premium)
        if case .subscribed(let date) = service.status {
            #expect(date == expiresDate)
        } else {
            Issue.record("Expected .subscribed status")
        }
    }

    // MARK: - refreshStatus: Trial

    @Test("试用期第 1 天 → tier=premium, status=trial(29)")
    func testTrialDay1() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil
        )
        provider.originalPurchaseDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()

        #expect(service.tier == .premium)
        if case .trial(let days) = service.status {
            #expect(days == 29)
        } else {
            Issue.record("Expected .trial status")
        }
    }

    @Test("试用期第 30 天 → tier=premium, status=trial(0)")
    func testTrialLastDay() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil
        )
        provider.originalPurchaseDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()

        // 第 30 天: daysSinceInstall == 30, 30 < 30 is false → expired
        #expect(service.tier == .free)
        #expect(service.status == .expired)
    }

    @Test("试用期第 31 天 → tier=free, status=expired")
    func testTrialExpired() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil
        )
        provider.originalPurchaseDate = Calendar.current.date(byAdding: .day, value: -31, to: Date())
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()

        #expect(service.tier == .free)
        #expect(service.status == .expired)
    }

    // MARK: - refreshStatus: No entitlements, no trial

    @Test("无权益无试用 → tier=free, status=expired")
    func testNoEntitlements() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil
        )
        provider.originalPurchaseDate = nil
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()

        #expect(service.tier == .free)
        #expect(service.status == .expired)
    }

    // MARK: - refreshStatus: Priority

    @Test("终身买断优先于订阅")
    func testLifetimePriority() async {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: true,
            hasActiveSubscription: true,
            subscriptionExpirationDate: Date().addingTimeInterval(365 * 24 * 3600)
        )
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()

        #expect(service.status == .lifetime)
    }

    // MARK: - restorePurchases

    @Test("恢复购买失败设置 restoreError")
    func testRestoreError() async {
        let provider = FailingSubscriptionProvider()
        let service = SubscriptionService(provider: provider)
        await service.restorePurchases()

        #expect(service.restoreError != nil)
    }

    // MARK: - Helpers

    private func makeService(tier: SubscriptionTier) async -> SubscriptionService {
        let provider = MockSubscriptionProvider()
        switch tier {
        case .premium:
            provider.entitlementState = EntitlementState(
                hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil
            )
        case .free:
            provider.entitlementState = EntitlementState(
                hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil
            )
            provider.originalPurchaseDate = nil
        }
        let service = SubscriptionService(provider: provider)
        await service.refreshStatus()
        return service
    }
}

// MARK: - AppError Subscription Tests

@Suite("AppError 订阅错误码测试")
struct SubscriptionAppErrorTests {

    @Test("SUB001 错误码正确")
    func testSUB001() {
        let error = AppError.purchaseFailed("商品不存在")
        #expect(error.errorCode == "SUB001")
        #expect(error.errorDescription?.contains("购买失败") == true)
    }

    @Test("SUB002 错误码正确")
    func testSUB002() {
        let error = AppError.featureRequiresPremium("losslessPlayback")
        #expect(error.errorCode == "SUB002")
        #expect(error.errorDescription?.contains("Premium") == true)
    }

    @Test("featureRequiresPremium Equatable 比较正确")
    func testFeatureRequiresPremiumEquatable() {
        let a = AppError.featureRequiresPremium("losslessPlayback")
        let b = AppError.featureRequiresPremium("losslessPlayback")
        let c = AppError.featureRequiresPremium("premiumTheme")
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - FailingSubscriptionProvider

private final class FailingSubscriptionProvider: SubscriptionProviding {
    func fetchProducts() async throws -> [SubscriptionProduct] { [] }
    func purchase(_ productID: String) async throws -> PurchaseResult { .cancelled }
    func restorePurchases() async throws {
        throw NSError(domain: "test", code: -1)
    }
    func resolveEntitlements() async -> EntitlementState {
        EntitlementState(hasLifetime: false, hasActiveSubscription: false, subscriptionExpirationDate: nil)
    }
    func appOriginalPurchaseDate() async -> Date? { nil }
    func transactionUpdates() -> AsyncStream<TransactionUpdate> {
        AsyncStream { $0.finish() }
    }
}

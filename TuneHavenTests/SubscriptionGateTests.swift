import Testing
import Foundation
@testable import TuneHaven

// MARK: - Playback lossless gate

@Suite("无损播放门禁")
@MainActor
struct LosslessPlaybackGateTests {

    @Test("Free 的 ensureCanPlay 拒绝无损并给出付费墙信号")
    func testEnsureCanPlayRejectsLosslessForFree() async {
        let harness = await makeHarness(premium: false)
        let song = makeFormatSong(format: "flac", title: "无损")
        #expect(harness.playback.ensureCanPlay(song) == false)
        #expect(harness.playback.losslessBlockedSong?.id == song.id)
        #expect(harness.engine.playCalled == false)
    }

    @Test("Premium 与有损歌曲可以通过 ensureCanPlay")
    func testEnsureCanPlayAllowsPremiumAndLossy() async {
        let premium = await makeHarness(premium: true)
        let flac = makeFormatSong(format: "flac", title: "无损")
        #expect(premium.playback.ensureCanPlay(flac) == true)
        #expect(premium.playback.losslessBlockedSong == nil)

        let free = await makeHarness(premium: false)
        let mp3 = makeFormatSong(format: "mp3", title: "有损")
        #expect(free.playback.ensureCanPlay(mp3) == true)
    }

    @Test("Free 的 play/prepare 不会加载或播放无损")
    func testPlayAndPrepareBlocked() async {
        let harness = await makeHarness(premium: false)
        let song = makeFormatSong(format: "flac", title: "无损")
        await harness.playback.play(song: song, in: .queue)
        #expect(harness.playback.currentSong == nil)
        #expect(harness.engine.loadCalled == false)
        #expect(harness.engine.playCalled == false)
        #expect(harness.playback.losslessBlockedSong?.id == song.id)

        harness.playback.clearLosslessBlock()
        harness.engine.loadCalled = false
        await harness.playback.prepare(song: song, in: .queue)
        #expect(harness.engine.loadCalled == false)
        #expect(harness.playback.losslessBlockedSong?.id == song.id)
    }

    @Test("Free 仍可播放有损，锁屏 Play 在暂停后会恢复")
    func testLossyPlayAndRemotePlay() async {
        let harness = await makeHarness(premium: false)
        let song = makeFormatSong(format: "mp3", title: "有损")
        await harness.playback.play(song: song, in: .queue)
        #expect(harness.playback.currentSong?.id == song.id)
        #expect(harness.engine.playCalled == true)

        harness.engine.state = .paused
        harness.engine.playCalled = false
        harness.nowPlaying.onPlayHandler?()
        await waitUntil { harness.engine.playCalled }
        #expect(harness.engine.playCalled == true)
        #expect(harness.playback.losslessBlockedSong == nil)
    }

    @Test("锁屏 Play 不能绕过无损门禁")
    func testRemotePlayBlocked() async {
        let harness = await makeHarness(premium: true)
        let song = makeFormatSong(format: "flac", title: "无损")
        await harness.playback.play(song: song, in: .queue)
        await downgradeToFree(harness)
        await waitUntil { harness.engine.pauseCalled }

        harness.engine.playCalled = false
        harness.nowPlaying.onPlayHandler?()
        await flushMainActor()
        #expect(harness.engine.playCalled == false)
        #expect(harness.playback.isPlaying == false)
        #expect(harness.playback.losslessBlockedSong?.id == song.id)
    }

    @Test("togglePlayPause 不能恢复 Free 的无损")
    func testToggleBlocked() async {
        let harness = await makeHarness(premium: true)
        let song = makeFormatSong(format: "flac", title: "无损")
        await harness.playback.play(song: song, in: .queue)
        harness.engine.state = .paused
        harness.engine.playCalled = false
        await downgradeToFree(harness)
        await flushMainActor()

        harness.engine.playCalled = false
        harness.playback.togglePlayPause()
        #expect(harness.engine.playCalled == false)
        #expect(harness.playback.losslessBlockedSong?.id == song.id)
    }

    @Test("Free 冷启动不把无损恢复为 currentSong，有损可以恢复")
    func testRestoreLastPlayed() async {
        let blocked = await makeHarness(premium: false)
        let flac = makeFormatSong(format: "flac", title: "上次无损")
        blocked.songs.songs = [flac]
        blocked.preferences.lastPlayedSongId = flac.id.uuidString
        await blocked.playback.restoreLastPlayedSong()
        #expect(blocked.playback.currentSong == nil)
        #expect(blocked.playback.queue.count == 0)
        #expect(blocked.playback.losslessBlockedSong == nil)

        let allowed = await makeHarness(premium: false)
        let mp3 = makeFormatSong(format: "mp3", title: "上次有损")
        allowed.songs.songs = [mp3]
        allowed.preferences.lastPlayedSongId = mp3.id.uuidString
        await allowed.playback.restoreLastPlayedSong()
        #expect(allowed.playback.currentSong?.id == mp3.id)
        #expect(allowed.playback.queue.count == 1)
    }

    @Test("Premium 可以恢复上次无损歌曲")
    func testPremiumRestoresLossless() async {
        let harness = await makeHarness(premium: true)
        let flac = makeFormatSong(format: "flac", title: "上次无损")
        harness.songs.songs = [flac]
        harness.preferences.lastPlayedSongId = flac.id.uuidString
        await harness.playback.restoreLastPlayedSong()
        #expect(harness.playback.currentSong?.id == flac.id)
        #expect(harness.engine.playCalled == false)
    }

    @Test("下一首遇到无损时停在该首并弹软墙，不静默跳到后面的有损")
    func testPlayNextParksOnLossless() async {
        let harness = await makeHarness(premium: false)
        let first = makeFormatSong(format: "mp3", title: "A")
        let blocked = makeFormatSong(format: "flac", title: "B")
        let after = makeFormatSong(format: "mp3", title: "C")
        harness.playback.queue.replaceQueue(with: [first, blocked, after], startAt: 0)
        await harness.playback.play(song: first, in: .queue)
        harness.engine.playCalled = false
        harness.engine.loadCalled = false

        harness.playback.playNext()
        #expect(harness.playback.currentSong?.id == blocked.id)
        #expect(harness.playback.losslessBlockedSong?.id == blocked.id)
        #expect(harness.playback.isPlaying == false)
        #expect(harness.engine.playCalled == false)
        #expect(harness.engine.loadCalled == false)
        #expect(harness.engine.stopCalled == true)
    }

    @Test("上一首遇到无损时同样停在目标首")
    func testPlayPreviousParksOnLossless() async {
        let harness = await makeHarness(premium: false)
        let blocked = makeFormatSong(format: "flac", title: "上一首")
        let current = makeFormatSong(format: "mp3", title: "当前")
        harness.playback.queue.replaceQueue(with: [blocked, current], startAt: 1)
        await harness.playback.play(song: current, in: .queue)
        harness.engine.currentTime = 0
        harness.engine.playCalled = false
        harness.engine.loadCalled = false

        harness.playback.playPrevious()
        #expect(harness.playback.currentSong?.id == blocked.id)
        #expect(harness.playback.losslessBlockedSong?.id == blocked.id)
        #expect(harness.engine.playCalled == false)
        #expect(harness.engine.loadCalled == false)
    }

    @Test("档位降为 Free 时暂停正在播放的无损，不打断有损")
    func testTierDropPausesOnlyLossless() async {
        let lossy = await makeHarness(premium: true)
        let mp3 = makeFormatSong(format: "mp3", title: "有损")
        await lossy.playback.play(song: mp3, in: .queue)
        await downgradeToFree(lossy)
        await flushMainActor()
        await flushMainActor()
        #expect(lossy.engine.pauseCalled == false)
        #expect(lossy.playback.isPlaying == true)
        #expect(lossy.playback.losslessBlockedSong == nil)

        let lossless = await makeHarness(premium: true)
        let flac = makeFormatSong(format: "flac", title: "无损")
        await lossless.playback.play(song: flac, in: .queue)
        await downgradeToFree(lossless)
        await waitUntil { lossless.engine.pauseCalled }
        #expect(lossless.engine.pauseCalled == true)
        #expect(lossless.playback.isPlaying == false)
        #expect(lossless.playback.losslessBlockedSong?.id == flac.id)
    }
}

// MARK: - Theme downgrade

@Suite("免费主题降级", .serialized)
@MainActor
struct FreeThemeDowngradeTests {

    @Test("已知 Free 后，已保存的高级主题降为素云白简")
    func testApplyFreeDowngradesPremiumTheme() {
        let previous = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle)
        defer { restoreTheme(previous) }
        UserDefaults.standard.set("twilight_rose", forKey: AppStorageKey.themeStyle)
        ThemeRegistry.shared.bootstrap()
        let manager = ThemeManager()
        #expect(manager.currentStyle.id == "twilight_rose")

        manager.applyTier(.free)
        #expect(manager.currentStyle.id == "cloud_white")
        #expect(UserDefaults.standard.string(forKey: AppStorageKey.themeStyle) == "cloud_white")
    }

    @Test("免费主题与 Premium 档位不会被强制改掉")
    func testFreeThemeAndPremiumTierStay() {
        let previous = UserDefaults.standard.string(forKey: AppStorageKey.themeStyle)
        defer { restoreTheme(previous) }

        UserDefaults.standard.set("azure_sky", forKey: AppStorageKey.themeStyle)
        ThemeRegistry.shared.bootstrap()
        let freeTheme = ThemeManager()
        freeTheme.applyTier(.free)
        #expect(freeTheme.currentStyle.id == "azure_sky")

        UserDefaults.standard.set("cosmic_tech", forKey: AppStorageKey.themeStyle)
        let premium = ThemeManager()
        premium.applyTier(.premium)
        #expect(premium.currentStyle.id == "cosmic_tech")
        premium.applyTier(.free)
        #expect(premium.currentStyle.id == "cloud_white")
    }

    private func restoreTheme(_ previous: String?) {
        if let previous {
            UserDefaults.standard.set(previous, forKey: AppStorageKey.themeStyle)
        } else {
            UserDefaults.standard.removeObject(forKey: AppStorageKey.themeStyle)
        }
    }
}

// MARK: - WebDAV domain gate

@Suite("WebDAV Domain 门禁")
@MainActor
struct WebDAVDomainGateTests {

    @Test("Free 的 connect 与 downloadAndImport 在接触网络前拒绝")
    func testFreeRejectedBeforeNetwork() async {
        let fixture = await makeWebDAV(premium: false)
        let account = WebDAVAccount(serverURL: "https://dav.example.com", username: "user")
        do {
            try await fixture.service.connect(to: account)
            Issue.record("Free 用户不应连上 WebDAV")
        } catch let error as AppError {
            #expect(error == .featureRequiresPremium("webDAVImport"))
        } catch {
            Issue.record("意外错误 \(error)")
        }
        #expect(fixture.factory.madeClient == false)

        let file = WebDAVFile(
            href: "/a.flac",
            displayName: "a.flac",
            contentLength: 128,
            contentType: "audio/flac",
            lastModified: nil,
            isDirectory: false,
            etag: nil
        )
        let result = await fixture.service.downloadAndImport(files: [file]) { _ in }
        #expect(result.downloadedCount == 0)
        #expect(result.downloadFailedCount == 1)
        #expect(result.errors.first?.contains("Premium") == true)
        #expect(fixture.client.downloadCalled == false)
    }

    @Test("Premium 的 connect 会创建客户端")
    func testPremiumConnectReachesClient() async {
        let fixture = await makeWebDAV(premium: true)
        let account = WebDAVAccount(serverURL: "https://dav.example.com", username: "user")
        try? await fixture.service.connect(to: account)
        #expect(fixture.factory.madeClient == true)
    }
}

// MARK: - App URLs

@Suite("AppURLs")
struct AppURLTests {

    @Test("隐私政策与管理订阅链接固定为提审用地址")
    func testCanonicalURLs() {
        #expect(AppURLs.privacyPolicy.absoluteString == "https://tunehaven.app/privacy")
        #expect(AppURLs.manageSubscriptions.absoluteString == "https://apps.apple.com/account/subscriptions")
    }
}

// MARK: - Harness

@MainActor
private struct PlaybackHarness {
    let playback: PlaybackService
    let engine: MockAudioEngine
    let nowPlaying: MockNowPlayingManaging
    let preferences: MockUserPreferences
    let songs: MockSongRepository
    let subscription: SubscriptionService
    let provider: MockSubscriptionProvider
}

@MainActor
private func makeHarness(premium: Bool) async -> PlaybackHarness {
    let provider = MockSubscriptionProvider()
    if premium {
        provider.entitlementState = EntitlementState(
            hasLifetime: true,
            hasActiveSubscription: false,
            subscriptionExpirationDate: nil
        )
    }
    let subscription = SubscriptionService(provider: provider)
    if premium {
        await subscription.refreshStatus()
    }
    let engine = MockAudioEngine()
    let nowPlaying = MockNowPlayingManaging()
    let preferences = MockUserPreferences()
    let songs = MockSongRepository()
    let playback = PlaybackService(
        playlistRepo: MockPlaylistRepository(),
        songRepo: songs,
        queueService: PlayQueueService(),
        libraryService: MusicLibraryService(songRepo: songs, imageCache: MockImageCacheManaging()),
        engine: engine,
        audioSession: MockAudioSessionManaging(),
        nowPlaying: nowPlaying,
        fileStorage: MockFileStorageProviding(),
        preferences: preferences,
        sleepTimer: SleepTimerService(),
        subscriptionService: subscription
    )
    return PlaybackHarness(
        playback: playback,
        engine: engine,
        nowPlaying: nowPlaying,
        preferences: preferences,
        songs: songs,
        subscription: subscription,
        provider: provider
    )
}

@MainActor
private func downgradeToFree(_ harness: PlaybackHarness) async {
    harness.provider.entitlementState = EntitlementState(
        hasLifetime: false,
        hasActiveSubscription: false,
        subscriptionExpirationDate: nil
    )
    harness.provider.originalPurchaseDate = Date().addingTimeInterval(-40 * 24 * 3600)
    await harness.subscription.refreshStatus()
}

private func flushMainActor() async {
    for _ in 0..<5 {
        await Task.yield()
    }
}

private func waitUntil(_ predicate: () -> Bool) async {
    for _ in 0..<20 {
        if predicate() { return }
        await Task.yield()
    }
}

private func makeFormatSong(format: String, title: String) -> Song {
    Song(
        id: UUID(),
        title: title,
        artist: "Artist",
        album: "Album",
        duration: 180,
        fileHash: UUID().uuidString,
        fileRelativePath: "\(title).\(format)",
        coverImagePath: nil,
        lyricsPath: nil,
        lyricsSource: nil,
        metadata: Metadata(
            format: format,
            sampleRate: 44100,
            bitRate: format == "mp3" ? 320 : 900,
            channels: 2,
            encoder: nil,
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

@MainActor
private struct WebDAVFixture {
    let service: WebDAVService
    let factory: StubWebDAVFactory
    let client: StubWebDAVClient
}

@MainActor
private func makeWebDAV(premium: Bool) async -> WebDAVFixture {
    let provider = MockSubscriptionProvider()
    if premium {
        provider.entitlementState = EntitlementState(
            hasLifetime: true,
            hasActiveSubscription: false,
            subscriptionExpirationDate: nil
        )
    }
    let subscription = SubscriptionService(provider: provider)
    if premium {
        await subscription.refreshStatus()
    }
    let client = StubWebDAVClient()
    let factory = StubWebDAVFactory(client: client)
    let service = WebDAVService(
        accountStore: StubWebDAVAccountStore(),
        clientFactory: factory,
        importService: StubFileImporting(),
        fileStorage: MockFileStorageProviding(),
        subscriptionService: subscription
    )
    return WebDAVFixture(service: service, factory: factory, client: client)
}

private final class StubWebDAVAccountStore: WebDAVAccountStoring {
    func loadAccounts() -> [WebDAVAccount] { [] }
    func saveAccount(_ account: WebDAVAccount, password: String?) throws {}
    func deleteAccount(id: UUID) throws {}
    func password(for accountId: UUID) -> String? { "secret" }
    func updateLastConnected(accountId: UUID) throws {}
}

private final class StubWebDAVFactory: WebDAVClientFactory {
    let client: StubWebDAVClient
    var madeClient = false
    init(client: StubWebDAVClient) { self.client = client }
    func makeClient(baseURL: URL, username: String, password: String, trustSelfSignedCert: Bool) -> WebDAVClientProtocol {
        madeClient = true
        return client
    }
}

private final class StubWebDAVClient: WebDAVClientProtocol, @unchecked Sendable {
    var downloadCalled = false
    func testConnection() async throws -> Bool { true }
    func listDirectory(path: String) async throws -> [WebDAVFile] { [] }
    func downloadFile(
        remotePath: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        downloadCalled = true
        return destination
    }
    func cancelDownload() async {}
}

@MainActor
private final class StubFileImporting: FileImporting {
    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
        ImportResult(
            successCount: 0,
            skippedDuplicateCount: 0,
            skippedFormatCount: 0,
            failedCount: 0,
            incompleteMetadataCount: 0,
            skippedOversizeCount: 0,
            details: []
        )
    }
}

import Foundation
import Testing
@testable import TuneHaven

@Suite("歌词加载状态与持久化")
@MainActor
struct LyricsLoadStateTests {
    private func makeService(repo: SongRepository = MockSongRepository(), api: TestLyricsAPI = TestLyricsAPI(),
                             preferences: MockUserPreferences = MockUserPreferences(),
                             storage: MockFileStorageProviding = MockFileStorageProviding(),
                             embedded: MockEmbeddedLyricsReader = MockEmbeddedLyricsReader(), premium: Bool = true) async -> LyricsService {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(hasLifetime: premium, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        let subscription = SubscriptionService(provider: provider)
        await subscription.refreshStatus()
        return LyricsService(repo: repo, api: api, preferences: preferences, fileStorage: storage,
                             embeddedReader: embedded, subscriptionService: subscription)
    }

    @Test("匹配中回调先于请求，无结果进入七天缓存")
    func noResults() async {
        let api = TestLyricsAPI()
        let service = await makeService(api: api)
        let song = makeSong()
        var matching = false
        api.onGet = { #expect(matching) }
        #expect(await service.loadLyricsResult(for: song, onMatching: { matching = true }).state == .notFound)
        #expect(matching)
        #expect(await service.loadLyricsResult(for: song).state == .notFound)
        #expect(api.getCalls == 1)
    }

    @Test("精确请求失败不会误记无结果，重试仍发出请求")
    func exactNetworkFailure() async {
        let api = TestLyricsAPI()
        api.getError = URLError(.notConnectedToInternet)
        let preferences = MockUserPreferences()
        let service = await makeService(api: api, preferences: preferences)
        let song = makeSong()
        #expect(await service.loadLyricsResult(for: song).state == .networkError)
        #expect(preferences.lyricsCooldown.isEmpty)
        api.getError = nil
        #expect(await service.loadLyricsResult(for: song).state == .notFound)
        #expect(api.getCalls == 2)
    }

    @Test("搜索网络失败可重试，Free 与关闭自动匹配不联网")
    func searchFailureAndPermissions() async {
        let api = TestLyricsAPI()
        api.searchError = URLError(.timedOut)
        let service = await makeService(api: api)
        #expect(await service.loadLyricsResult(for: makeSong()).state == .networkError)
        let free = await makeService(api: api, premium: false)
        #expect(await free.loadLyricsResult(for: makeSong()).state == .unavailable)
        let preferences = MockUserPreferences()
        preferences.autoMatchLyrics = false
        let disabled = await makeService(api: api, preferences: preferences)
        #expect(await disabled.loadLyricsResult(for: makeSong()).state == .unavailable)
        #expect(api.getCalls == 1)
    }

    @Test("纯文本歌词没有虚构时间轴")
    func plainLyrics() async {
        let embedded = MockEmbeddedLyricsReader()
        embedded.result = "第一行\n第二行"
        let service = await makeService(embedded: embedded)
        let result = await service.loadLyricsResult(for: makeSong())
        #expect(result.state == .loaded)
        #expect(result.data?.lines.isEmpty == true)
        #expect(result.data?.rawText == embedded.result)
    }

    @Test("器乐曲经 Core Data 保存，重建服务后读取；添加歌词可替换标记")
    func instrumentalPersistence() async throws {
        let stack = try await CoreDataStack.makeInMemory()
        let repo = CoreDataSongRepository(stack: stack)
        let song = makeSong()
        try await repo.insert(song: song)
        let api = TestLyricsAPI()
        api.track = instrumentalTrack()
        let service = await makeService(repo: repo, api: api)
        #expect(await service.loadLyricsResult(for: song).state == .instrumental)
        let reloaded = await makeService(repo: repo, api: api)
        #expect(await reloaded.loadLyricsResult(for: song).state == .instrumental)
        #expect(api.getCalls == 1)
        try await reloaded.saveLyrics("[00:01.00]新歌词", for: song)
        defer { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("\(song.id).lrc")) }
        #expect(await repo.fetchSong(id: song.id)?.lyricsSource == .file)
    }

    @Test("取消匹配后不保存迟到的器乐曲结果")
    func cancellation() async {
        let repo = MockSongRepository()
        let song = makeSong()
        repo.songs = [song]
        let api = TestLyricsAPI()
        api.track = instrumentalTrack()
        api.shouldWait = true
        let service = await makeService(repo: repo, api: api)
        let task = Task { await service.loadLyricsResult(for: song) }
        while api.continuation == nil { await Task.yield() }
        task.cancel()
        api.continuation?.resume()
        #expect(await task.value.state == .unavailable)
        #expect(repo.songs.first?.lyricsSource == nil)
    }

    @Test("手动添加后迟到的自动结果不能覆盖用户选择")
    func manualChoiceWins() async throws {
        let repo = MockSongRepository()
        let song = makeSong()
        repo.songs = [song]
        let api = TestLyricsAPI()
        api.track = instrumentalTrack()
        api.shouldWait = true
        let service = await makeService(repo: repo, api: api)
        let task = Task { await service.loadLyricsResult(for: song) }
        while api.continuation == nil { await Task.yield() }
        try await service.saveLyrics("手动歌词", for: song)
        defer { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("\(song.id).lrc")) }
        api.continuation?.resume()
        #expect(await task.value.state == .unavailable)
        #expect(repo.songs.first?.lyricsSource == .file)
    }

    @Test("歌曲标题不能让旧歌词清理越出歌词目录")
    func unsafeTitle() async throws {
        let storage = MockFileStorageProviding()
        let service = await makeService(storage: storage)
        let song = makeSong(title: "../outside")
        try await service.saveLyrics("歌词", for: song)
        defer { try? FileManager.default.removeItem(at: storage.lyricsFileURL(relativePath: "\(song.id).lrc")) }
        #expect(storage.removedItems.isEmpty)
    }

    @Test("器乐曲落盘返回较慢时，不清理后来手动添加的歌词文件")
    func delayedInstrumentalSaveDoesNotRemoveManualLyrics() async throws {
        let repo = MockSongRepository()
        let song = makeSong()
        repo.songs = [song]
        var pending: CheckedContinuation<Void, Never>?
        repo.onLyricsUpdated = { source in
            if source == .instrumental { await withCheckedContinuation { pending = $0 } }
        }
        let storage = MockFileStorageProviding()
        let service = await makeService(repo: repo, storage: storage)
        let task = Task { try await service.markInstrumental(for: song) }
        while pending == nil { await Task.yield() }
        try await service.saveLyrics("后来添加的歌词", for: song)
        defer { try? FileManager.default.removeItem(at: storage.lyricsFileURL(relativePath: "\(song.id).lrc")) }
        pending?.resume()
        try await task.value
        #expect(repo.songs.first?.lyricsSource == .file)
        #expect(!storage.removedItems.contains(storage.lyricsFileURL(relativePath: "\(song.id).lrc")))
    }

    @Test("元数据备份恢复保留器乐曲标记，不要求歌词文件")
    func backupInstrumental() throws {
        let id = UUID()
        var record = BackupTestFiles.record(id: id, title: "纯音乐", audio: nil)
        record.lyricsSource = Int(LyricsSource.instrumental.rawValue)
        let decoded = try JSONDecoder().decode(BackupSongRecord.self, from: JSONEncoder().encode(record))
        let plan = BackupPlanner.plan(local: BackupTestFiles.snapshot(songs: []),
                                      package: BackupTestFiles.catalog(songs: [decoded]), mode: .replaceLibrary,
                                      resolution: BackupTestFiles.resolution(song: .replace))
        #expect(plan.snapshot.songs.first?.song.lyricsSource == .instrumental)
        #expect(plan.snapshot.songs.first?.song.lyricsPath == nil)
    }

    @Test("删除内嵌歌词后重启不再读回，也不自动联网；重新添加歌词可替换")
    func deletedEmbeddedLyricsStayDeleted() async throws {
        let stack = try await CoreDataStack.makeInMemory()
        let repo = CoreDataSongRepository(stack: stack)
        var song = makeSong()
        try await repo.insert(song: song)
        let embedded = MockEmbeddedLyricsReader()
        embedded.result = "[00:01.00]内嵌歌词"
        let api = TestLyricsAPI()
        let service = await makeService(repo: repo, api: api, embedded: embedded)
        #expect(await service.loadLyricsResult(for: song).state == .loaded)

        try await service.deleteLyrics(for: song)
        song = try #require(await repo.fetchSong(id: song.id))
        #expect(song.lyricsSource == .removed)

        let reloaded = await makeService(repo: repo, api: api, embedded: embedded)
        #expect(await reloaded.loadLyricsResult(for: song).state == .unavailable)
        #expect(api.getCalls == 0)

        try await reloaded.saveLyrics("[00:01.00]新歌词", for: song)
        defer { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("\(song.id).lrc")) }
        #expect(await repo.fetchSong(id: song.id)?.lyricsSource == .file)
    }

    @Test("备份恢复保留已删除歌词标记")
    func backupRemovedMarker() throws {
        let id = UUID()
        var record = BackupTestFiles.record(id: id, title: "删过歌词", audio: nil)
        record.lyricsSource = Int(LyricsSource.removed.rawValue)
        let plan = BackupPlanner.plan(local: BackupTestFiles.snapshot(songs: []),
                                      package: BackupTestFiles.catalog(songs: [record]), mode: .replaceLibrary,
                                      resolution: BackupTestFiles.resolution(song: .replace))
        #expect(plan.snapshot.songs.first?.song.lyricsSource == .removed)
        #expect(plan.snapshot.songs.first?.song.lyricsPath == nil)
    }

    private func instrumentalTrack() -> LRCLibTrack {
        LRCLibTrack(id: 1, trackName: "Test Song", artistName: "Test Artist",
                    albumName: "Test Album", duration: 180, instrumental: true, plainLyrics: nil, syncedLyrics: nil)
    }
}

private final class TestLyricsAPI: LyricsAPIProviding {
    var track: LRCLibTrack?
    var getError: Error?
    var searchError: Error?
    var getCalls = 0
    var onGet: (() -> Void)?
    var shouldWait = false
    var continuation: CheckedContinuation<Void, Never>?
    func get(trackName: String, artistName: String, albumName: String, duration: Int) async throws -> LRCLibTrack? {
        getCalls += 1
        onGet?()
        if shouldWait { await withCheckedContinuation { continuation = $0 } }
        if let getError { throw getError }
        return track
    }
    func search(trackName: String, artistName: String?) async throws -> [LRCLibTrack] {
        if let searchError { throw searchError }
        return []
    }
}

import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("分享接收：取消与分析失败")
struct ShareReceiveCancelTests {

    @Test("取歌单曲目时用户取消：不建歌单，抛出取消")
    func cancelDuringPlaylistPhaseCreatesNothing() async throws {
        let fixture = Fixture()
        let service = fixture.service
        _ = try await service.connectAndAnalyze(qrContent: "http://127.0.0.1:8090?token=t")
        fixture.client.onFetchPlaylistSongs = { [weak service] in
            // 分析阶段已取过一次，这是接收阶段
            if fixture.client.fetchPlaylistSongsCount > 1 { service?.cancelReceive() }
        }

        await #expect(throws: CancellationError.self) {
            _ = try await service.executeReceive()
        }
        #expect(fixture.playlistRepo.createdNames.isEmpty)
        #expect(service.transferResult == nil)
        #expect(fixture.client.notifiedComplete == false)
    }

    @Test("下载歌曲时取消：后续歌曲和歌单都不再处理")
    func cancelDuringSongPhaseStopsLoop() async throws {
        let fixture = Fixture()
        fixture.client.songs = [Self.song(0, "新歌一"), Self.song(1, "新歌二")]
        let service = fixture.service
        _ = try await service.connectAndAnalyze(qrContent: "http://127.0.0.1:8090?token=t")
        fixture.client.onDownloadAudio = { [weak service] in service?.cancelReceive() }

        await #expect(throws: CancellationError.self) {
            _ = try await service.executeReceive()
        }
        #expect(fixture.client.downloadCount == 1)
        #expect(fixture.playlistRepo.createdNames.isEmpty)
    }

    @Test("未取消时歌单照常创建")
    func receiveWithoutCancelCreatesPlaylist() async throws {
        let fixture = Fixture()
        let service = fixture.service
        _ = try await service.connectAndAnalyze(qrContent: "http://127.0.0.1:8090?token=t")

        let result = try await service.executeReceive()

        #expect(result.playlistsCreated == 1)
        #expect(fixture.playlistRepo.createdNames == ["歌单"])
        #expect(fixture.client.notifiedComplete)
    }

    @Test("分析时取歌单曲目失败：断开并复位，不停在准备中")
    func analysisPlaylistFailureResetsState() async {
        let fixture = Fixture()
        fixture.client.failFetchPlaylistSongs = true
        let service = fixture.service

        await #expect(throws: (any Error).self) {
            _ = try await service.connectAndAnalyze(qrContent: "http://127.0.0.1:8090?token=t")
        }
        #expect(service.isReceiving == false)
        #expect(service.receiveProgress == nil)
        #expect(fixture.client.disconnected)
    }

    nonisolated static func song(_ index: Int, _ title: String) -> ShareSongSummary {
        ShareSongSummary(index: index, title: title, artist: "歌手", album: "专辑",
                         duration: 200 + Double(index), fileSize: 1024, hasCover: false, hasLyrics: false)
    }

    @MainActor
    private struct Fixture {
        let client = ScriptedShareClient()
        let playlistRepo = RecordingPlaylistRepository()
        let service: ShareService

        init() {
            let fileStorage = MockFileStorageProviding()
            let songRepo = MockSongRepository()
            let client = client
            service = ShareService(
                songRepo: songRepo,
                playlistService: PlaylistService(repo: playlistRepo, songRepo: songRepo, coverProcessor: MockCoverImageProcessing()),
                groupService: PlaylistGroupService(repo: EmptyPlaylistGroupRepository()),
                importService: ImportService(songRepo: songRepo, fileService: fileStorage, coverProcessor: MockCoverImageProcessing(), metadataParser: MockAudioMetadataParsing()),
                fileStorage: fileStorage,
                backgroundTask: NoopBackgroundTask(),
                serverFactory: { ShareServer() },
                clientFactory: { client }
            )
        }
    }
}

@MainActor
private final class ScriptedShareClient: ShareClientProviding {
    var songs: [ShareSongSummary] = []
    var failFetchPlaylistSongs = false
    var onFetchPlaylistSongs: (() -> Void)?
    var onDownloadAudio: (() -> Void)?
    private(set) var fetchPlaylistSongsCount = 0
    private(set) var downloadCount = 0
    private(set) var notifiedComplete = false
    private(set) var disconnected = false

    func connect(to qrContent: String) async throws -> ShareSessionInfo {
        ShareSessionInfo(deviceName: "发送端", sessionToken: "t", songCount: songs.count, playlistCount: 1, totalSize: 0)
    }
    func fetchSongList() async throws -> [ShareSongSummary] { songs }
    func fetchPlaylistList() async throws -> [SharePlaylistSummary] {
        [SharePlaylistSummary(index: 0, name: "歌单", description: nil, groupName: nil, songCount: 1)]
    }
    func fetchPlaylistSongs(at index: Int) async throws -> [ShareSongSummary] {
        fetchPlaylistSongsCount += 1
        if failFetchPlaylistSongs { throw URLError(.networkConnectionLost) }
        onFetchPlaylistSongs?()
        return [ShareReceiveCancelTests.song(9, "歌单里的歌")]
    }
    func fetchSongMeta(at index: Int) async throws -> SongExportData { throw URLError(.unsupportedURL) }
    func downloadAudio(at index: Int, to dir: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> URL {
        downloadCount += 1
        onDownloadAudio?()
        throw URLError(.networkConnectionLost)
    }
    func downloadCover(at index: Int, to dir: URL) async throws -> URL? { nil }
    func downloadLyrics(at index: Int, to dir: URL) async throws -> URL? { nil }
    func notifyComplete(result: ShareTransferResult) async throws { notifiedComplete = true }
    func disconnect() { disconnected = true }
}

private final class RecordingPlaylistRepository: PlaylistRepository {
    private let base = MockPlaylistRepository()
    private(set) var createdNames: [String] = []

    func fetchAll() async -> [Playlist] { [] }
    func fetchPlaylistDetail(id: UUID) async -> PlaylistDetail? { nil }
    func create(name: String, description: String?) async throws -> Playlist {
        createdNames.append(name)
        return try await base.create(name: name, description: description)
    }
    func update(id: UUID, name: String?, description: String?) async throws {}
    func delete(id: UUID) async throws {}
    func addSongs(_ songIds: [UUID], to playlistId: UUID) async throws {}
    func removeSongs(_ songIds: [UUID], from playlistId: UUID) async throws {}
    func reorder(orderedIds: [UUID]) async throws {}
    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws {}
    func createSystemPlaylists() async throws {}
    func fetchFavoritesSongIds() async -> [UUID] { [] }
    func updateAutoCover(playlistId: UUID, path: String, hash: String) async throws {}
    func setCustomCover(playlistId: UUID, imagePath: String) async throws {}
}

private final class EmptyPlaylistGroupRepository: PlaylistGroupRepository {
    func fetchAll() async -> [PlaylistGroup] { [] }
    func fetchGroupDetails() async -> [PlaylistGroupDetail] { [] }
    func create(name: String) async throws -> PlaylistGroup { throw URLError(.unsupportedURL) }
    func rename(id: UUID, name: String) async throws {}
    func delete(id: UUID) async throws {}
    func movePlaylist(_ playlistId: UUID, toGroup groupId: UUID?) async throws {}
    func reorder(orderedIds: [UUID]) async throws {}
}

private struct NoopBackgroundTask: BackgroundTaskProviding {
    func beginTask(expirationHandler: (@Sendable () -> Void)?) -> UInt { 1 }
    func endTask(_ identifier: UInt) {}
}

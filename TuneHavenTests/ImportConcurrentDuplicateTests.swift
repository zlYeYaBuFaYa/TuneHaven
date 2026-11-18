import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("并发导入同一内容")
struct ImportConcurrentDuplicateTests {
    @Test("另一路先入库：返回已入库的记录与 id，按重复处理")
    func concurrentDuplicateReturnsStoredSong() async throws {
        let repo = MockSongRepository()
        repo.upsertsByHash = true
        let fileService = MockFileStorageProviding()
        let winner = makeSong(title: "先到的", fileHash: "mockhash12345678")
        // 本路的去重检查已过，写入前另一路抢先入库
        repo.beforeInsert = { _ in
            if repo.songs.isEmpty { repo.songs.append(winner) }
        }
        let service = ImportService(songRepo: repo, fileService: fileService,
                                    coverProcessor: MockCoverImageProcessing(), metadataParser: MockAudioMetadataParsing())

        let result = await service.processAppleMusicFile(
            tempURL: URL(fileURLWithPath: "/tmp/am-\(UUID()).m4a"), originalFilename: "a.m4a",
            title: "后到的", artist: nil, album: nil, coverData: nil
        )

        #expect(result.status == .skippedDuplicate)
        #expect(result.song?.id == winner.id)
        #expect(repo.songs.count == 1)
        #expect(await repo.fetchSong(id: try #require(result.song?.id)) != nil)
    }

    @Test("没有竞争时照常返回新记录")
    func normalImportReturnsNewSong() async {
        let repo = MockSongRepository()
        repo.upsertsByHash = true
        let service = ImportService(songRepo: repo, fileService: MockFileStorageProviding(),
                                    coverProcessor: MockCoverImageProcessing(), metadataParser: MockAudioMetadataParsing())

        let result = await service.processAppleMusicFile(
            tempURL: URL(fileURLWithPath: "/tmp/am-\(UUID()).m4a"), originalFilename: "a.m4a",
            title: "唯一", artist: nil, album: nil, coverData: nil
        )

        #expect(result.status == .success)
        #expect(result.song?.id == repo.songs.first?.id)
    }
}

import Testing
import Foundation
import CoreData
@testable import TuneHaven

// MARK: - CoreDataSongRepository（内存库）

@Suite("CoreDataSongRepository Tests")
struct CoreDataSongRepositoryTests {

    private func makeRepos() async throws -> (CoreDataStack, CoreDataSongRepository, CoreDataPlaylistRepository) {
        let stack = try await CoreDataStack.makeInMemory()
        return (stack, CoreDataSongRepository(stack: stack), CoreDataPlaylistRepository(stack: stack))
    }

    private func linkCount(songId: UUID, stack: CoreDataStack) async throws -> Int {
        try await stack.performBackground { ctx in
            let request = PlaylistSongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "songId == %@", songId as CVarArg)
            return try ctx.count(for: request)
        }
    }

    @Test("普通插入后可按 id 取到")
    func testInsert() async throws {
        let (_, repo, _) = try await makeRepos()
        let song = makeSong()

        try await repo.insert(song: song)

        #expect(await repo.fetchSong(id: song.id)?.id == song.id)
    }

    @Test("同哈希的未删除记录存在时只更新，不新增")
    func testInsertUpdatesActiveDuplicate() async throws {
        let (_, repo, _) = try await makeRepos()
        let original = makeSong(title: "Old", fileHash: "hash-a")
        try await repo.insert(song: original)

        try await repo.insert(song: makeSong(title: "New", fileHash: "hash-a"))

        let all = try await repo.fetchAll(sortBy: .title, ascending: true)
        #expect(all.count == 1)
        #expect(all.first?.id == original.id)
        #expect(all.first?.title == "New")
    }

    @Test("软删除后重导同一文件：得到可见的新记录，旧 id 消失")
    func testReimportAfterSoftDelete() async throws {
        let (_, repo, _) = try await makeRepos()
        let old = makeSong(fileHash: "hash-b")
        try await repo.insert(song: old)
        _ = try await repo.softDelete(ids: [old.id])

        let reimported = makeSong(fileHash: "hash-b")
        try await repo.insert(song: reimported)

        #expect(await repo.fetchSong(id: reimported.id) != nil)
        #expect(await repo.fetchSong(id: old.id) == nil)
        #expect(await repo.fetchByHash("hash-b")?.id == reimported.id)
        #expect(try await repo.fetchAll(sortBy: .title, ascending: true).map(\.id) == [reimported.id])
    }

    @Test("重导时清除旧记录的歌单链接")
    func testReimportRemovesOldPlaylistLinks() async throws {
        let (stack, repo, playlists) = try await makeRepos()
        let old = makeSong(fileHash: "hash-c")
        try await repo.insert(song: old)
        let playlist = try await playlists.create(name: "P", description: nil)
        try await playlists.addSongs([old.id], to: playlist.id)
        _ = try await repo.softDelete(ids: [old.id])

        try await repo.insert(song: makeSong(fileHash: "hash-c"))

        #expect(try await linkCount(songId: old.id, stack: stack) == 0)
    }

    @Test("重导后执行旧 token 的提交删除，新记录仍在")
    func testCommitDeleteAfterReimportKeepsNewSong() async throws {
        let (_, repo, _) = try await makeRepos()
        let old = makeSong(fileHash: "hash-d")
        try await repo.insert(song: old)
        let token = try await repo.softDelete(ids: [old.id])
        let reimported = makeSong(fileHash: "hash-d")
        try await repo.insert(song: reimported)

        try await repo.commitDelete(token: token)

        #expect(await repo.fetchSong(id: reimported.id) != nil)
    }

    @Test("撤销窗口已过时重导，启动清理不删除新记录")
    func testCleanupAfterReimportKeepsNewSong() async throws {
        let (stack, repo, _) = try await makeRepos()
        let old = makeSong(fileHash: "hash-e")
        try await repo.insert(song: old)
        _ = try await repo.softDelete(ids: [old.id])
        let oldId = old.id
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", oldId as CVarArg)
            try ctx.fetch(request).forEach { $0.deletedAt = Date().addingTimeInterval(-60) }
        }
        let reimported = makeSong(fileHash: "hash-e")
        try await repo.insert(song: reimported)

        await repo.cleanupPendingDeletes()

        #expect(await repo.fetchSong(id: reimported.id) != nil)
    }
}

import Foundation
import Testing
@testable import TuneHaven

@Suite("歌单排序持久化")
@MainActor
struct PlaylistOrderTests {
    private func removeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    @Test("歌曲顺序落盘，重读保持顺序且歌曲内容不变")
    func persistentSongOrder() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("order-\(UUID()).sqlite")
        defer { removeStore(at: url) }
        let stack = try await CoreDataStack.makeSQLiteForTesting(at: url)
        let songsRepo = CoreDataSongRepository(stack: stack)
        let repo = CoreDataPlaylistRepository(stack: stack)
        let songs = makeSongs(count: 3)
        for song in songs { try await songsRepo.insert(song: song) }
        let playlist = try await repo.create(name: "排序测试", description: nil)
        try await repo.addSongs(songs.map(\.id), to: playlist.id)
        let order = [songs[2].id, songs[0].id, songs[1].id]
        let service = PlaylistService(repo: repo, songRepo: songsRepo, coverProcessor: MockCoverImageProcessing())
        try await service.reorderSongs(in: playlist.id, orderedSongIds: order)
        let reloaded = CoreDataPlaylistRepository(stack: stack)
        #expect(await reloaded.fetchPlaylistDetail(id: playlist.id)?.songs.map(\.id) == order)
        #expect(try await songsRepo.fetchAll(sortBy: .title, ascending: true).count == 3)
    }

    @Test("内容变化和重复 ID 不覆盖现有排序")
    func staleOrderRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("order-\(UUID()).sqlite")
        defer { removeStore(at: url) }
        let stack = try await CoreDataStack.makeSQLiteForTesting(at: url)
        let songRepo = CoreDataSongRepository(stack: stack)
        let repo = CoreDataPlaylistRepository(stack: stack)
        let songs = makeSongs(count: 3)
        for song in songs { try await songRepo.insert(song: song) }
        let playlist = try await repo.create(name: "并发修改", description: nil)
        try await repo.addSongs(songs.map(\.id), to: playlist.id)
        await #expect(throws: AppError.self) {
            try await repo.reorderSongs(in: playlist.id, orderedSongIds: [songs[1].id, songs[0].id])
        }
        await #expect(throws: AppError.self) {
            try await repo.reorderSongs(in: playlist.id, orderedSongIds: [songs[0].id, songs[0].id, songs[2].id])
        }
        #expect(await repo.fetchPlaylistDetail(id: playlist.id)?.songs.map(\.id) == songs.map(\.id))
    }

    @Test("歌单顺序持久化，系统歌单不参与")
    func playlistOrder() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("order-\(UUID()).sqlite")
        defer { removeStore(at: url) }
        let stack = try await CoreDataStack.makeSQLiteForTesting(at: url)
        let repo = CoreDataPlaylistRepository(stack: stack)
        try await repo.createSystemPlaylists()
        let first = try await repo.create(name: "一", description: nil)
        let second = try await repo.create(name: "二", description: nil)
        try await repo.reorder(orderedIds: [second.id, first.id])
        #expect(await repo.fetchAll().filter { !$0.isSystem }.map(\.id) == [second.id, first.id])
        #expect(await repo.fetchAll().filter(\.isSystem).count == 2)
    }
}

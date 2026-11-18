import Foundation
import Testing
@testable import TuneHaven

@Suite("歌单仓库：读取新鲜度与去重")
@MainActor
struct PlaylistRepositoryFreshnessTests {
    private func makeStack() async throws -> (CoreDataStack, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("freshness-\(UUID()).sqlite")
        return (try await CoreDataStack.makeSQLiteForTesting(at: url), url)
    }

    private func removeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    @Test("传入重复的歌曲 id 只加一次")
    func addSongsDeduplicatesInput() async throws {
        let (stack, url) = try await makeStack()
        defer { removeStore(at: url) }
        let songRepo = CoreDataSongRepository(stack: stack)
        let repo = CoreDataPlaylistRepository(stack: stack)
        let songs = makeSongs(count: 2)
        for song in songs { try await songRepo.insert(song: song) }
        let playlist = try await repo.create(name: "去重", description: nil)

        try await repo.addSongs([songs[0].id, songs[1].id, songs[0].id], to: playlist.id)
        try await repo.addSongs([songs[1].id], to: playlist.id)

        let detail = try #require(await repo.fetchPlaylistDetail(id: playlist.id))
        #expect(detail.songs.map(\.id) == [songs[0].id, songs[1].id])
        #expect(detail.playlist.songCount == 2)
    }

    @Test("读过之后在后台改名、排序、改歌曲信息，再读拿到新值")
    func readsReflectBackgroundWrites() async throws {
        let (stack, url) = try await makeStack()
        defer { removeStore(at: url) }
        let songRepo = CoreDataSongRepository(stack: stack)
        let repo = CoreDataPlaylistRepository(stack: stack)
        let songs = makeSongs(count: 3)
        for song in songs { try await songRepo.insert(song: song) }
        let playlist = try await repo.create(name: "旧名", description: nil)
        try await repo.addSongs(songs.map(\.id), to: playlist.id)
        // 先读一次，让对象注册进 viewContext
        _ = await repo.fetchAll()
        _ = await repo.fetchPlaylistDetail(id: playlist.id)

        try await repo.update(id: playlist.id, name: "新名", description: nil)
        try await repo.reorderSongs(in: playlist.id, orderedSongIds: songs.map(\.id).reversed())
        try await songRepo.updateSongInfo(id: songs[0].id, title: "改过的标题", artist: "A", album: "B")

        let all = await repo.fetchAll()
        #expect(all.first { $0.id == playlist.id }?.name == "新名")
        let detail = try #require(await repo.fetchPlaylistDetail(id: playlist.id))
        #expect(detail.playlist.name == "新名")
        #expect(detail.songs.map(\.id) == songs.map(\.id).reversed())
        #expect(detail.songs.last?.title == "改过的标题")
    }
}

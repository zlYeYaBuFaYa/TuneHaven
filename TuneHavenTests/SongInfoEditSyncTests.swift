import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("编辑歌曲信息")
struct SongInfoEditSyncTests {
    @Test("艺术家、专辑留空时存为未知")
    func emptyArtistAlbumFallBackToUnknown() async throws {
        let harness = await makeHarness(premium: true)
        let song = makeSong(title: "原标题")
        harness.songs.songs = [song]

        try await harness.library.updateSongInfo(id: song.id, title: "新标题", artist: "  ", album: "")

        let stored = try #require(await harness.songs.fetchSong(id: song.id))
        #expect(stored.title == "新标题")
        #expect(stored.artist == SongDefaults.unknownArtist)
        #expect(stored.album == SongDefaults.unknownAlbum)
    }

    @Test("编辑正在播放的歌曲：播放器、队列和锁屏同步新信息")
    func editingCurrentSongRefreshesPlayback() async throws {
        let harness = await makeHarness(premium: true)
        let current = makeSong(title: "原标题")
        let other = makeSong(title: "另一首")
        harness.songs.songs = [current, other]
        await harness.playback.play(song: current, in: .allSongs(sortBy: .title))

        try await harness.library.updateSongInfo(id: current.id, title: "新标题", artist: "新歌手", album: "新专辑")
        await waitUntil { harness.playback.currentSong?.title == "新标题" }
        await waitUntil { harness.nowPlaying.lastUpdatedSong?.title == "新标题" }

        #expect(harness.playback.currentSong?.artist == "新歌手")
        #expect(harness.nowPlaying.lastUpdatedSong?.title == "新标题")
        #expect(harness.playback.queue.queue.first { $0.song.id == current.id }?.song.title == "新标题")
        #expect(harness.playback.queue.queue.first { $0.song.id == other.id }?.song.title == "另一首")
    }

    @Test("编辑非当前歌曲不改动当前歌曲")
    func editingOtherSongKeepsCurrent() async throws {
        let harness = await makeHarness(premium: true)
        let current = makeSong(title: "当前")
        let other = makeSong(title: "另一首")
        harness.songs.songs = [current, other]
        await harness.playback.play(song: current, in: .allSongs(sortBy: .title))

        try await harness.library.updateSongInfo(id: other.id, title: "改过", artist: "A", album: "B")
        await waitUntil { harness.playback.queue.queue.first { $0.song.id == other.id }?.song.title == "改过" }

        #expect(harness.playback.currentSong?.title == "当前")
        #expect(harness.playback.queue.queue.first { $0.song.id == other.id }?.song.title == "改过")
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

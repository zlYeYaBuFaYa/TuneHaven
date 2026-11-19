import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("继续听卡与迷你播放器交接")
struct ContinueListeningHandoffTests {
    @Test("冷启动恢复歌曲但未开播：仍由继续听卡承接")
    func restoreDoesNotCountAsStarted() async {
        let harness = await makeHarness(premium: true)
        let song = makeFormatSong(format: "mp3", title: "上次歌曲")
        harness.songs.songs = [song]
        harness.preferences.lastPlayedSongId = song.id.uuidString

        await harness.playback.restoreLastPlayedSong()

        #expect(harness.playback.currentSong?.id == song.id)
        #expect(harness.playback.hasStartedPlayback == false)
    }

    @Test("开播后交给迷你播放器，暂停也不退回")
    func startedStaysAfterPause() async {
        let harness = await makeHarness(premium: true)
        let song = makeFormatSong(format: "mp3", title: "上次歌曲")

        await harness.playback.play(song: song, in: .queue)
        #expect(harness.playback.hasStartedPlayback)

        harness.engine.pause()
        harness.engine.stateSubject.send(.paused)
        for _ in 0..<5 { await Task.yield() }
        #expect(harness.playback.isPlaying == false)
        #expect(harness.playback.hasStartedPlayback)
    }

    @Test("无损门禁拦下的播放不算开播")
    func blockedPlayIsNotStarted() async {
        let harness = await makeHarness(premium: false)
        let flac = makeFormatSong(format: "flac", title: "无损")

        await harness.playback.play(song: flac, in: .queue)

        #expect(harness.playback.hasStartedPlayback == false)
    }
}

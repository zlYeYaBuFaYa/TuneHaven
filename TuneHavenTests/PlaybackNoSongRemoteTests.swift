import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("没有当前歌曲时的播放控制")
struct PlaybackNoSongRemoteTests {
    @Test("锁屏 Play 不启动引擎、不置为播放中")
    func remotePlayWithoutSongDoesNothing() async {
        let harness = await makeHarness(premium: true)

        harness.nowPlaying.onPlayHandler?()
        await settle()

        #expect(harness.engine.playCalled == false)
        #expect(harness.playback.isPlaying == false)
    }

    @Test("播放／暂停切换同样不启动引擎")
    func toggleWithoutSongDoesNothing() async {
        let harness = await makeHarness(premium: true)

        harness.playback.togglePlayPause()
        harness.nowPlaying.onToggleHandler?()
        await settle()

        #expect(harness.engine.playCalled == false)
        #expect(harness.engine.state == .idle)
        #expect(harness.playback.isPlaying == false)
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }
}

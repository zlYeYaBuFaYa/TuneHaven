import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("上一首的 3 秒规则（交互验收 I-08）")
struct PreviousTrackRuleTests {
    private func playSecondOfTwo() async -> (PlaybackHarness, Song, Song) {
        let harness = await makeHarness(premium: true)
        let first = makeSong(title: "A 第一首")
        let second = makeSong(title: "B 第二首")
        harness.songs.songs = [first, second]
        harness.playback.queue.replaceQueue(with: [first, second], startAt: 1)
        await harness.playback.play(song: second, in: .queue)
        return (harness, first, second)
    }

    @Test("播放超过 3 秒：回到本曲开头，不切歌")
    func restartsCurrentAfterThreeSeconds() async {
        let (harness, _, second) = await playSecondOfTwo()
        harness.engine.currentTime = 10

        harness.playback.playPrevious()

        #expect(harness.playback.currentSong?.id == second.id)
        #expect(harness.engine.currentTime == 0)
    }

    @Test("3 秒以内：切到上一首")
    func goesToPreviousWithinThreeSeconds() async {
        let (harness, first, _) = await playSecondOfTwo()
        harness.engine.currentTime = 2

        harness.playback.playPrevious()
        for _ in 0..<20 where harness.playback.currentSong?.id != first.id { await Task.yield() }

        #expect(harness.playback.currentSong?.id == first.id)
    }

    @Test("恰好 3 秒算作开头附近，切到上一首")
    func exactlyThreeSecondsGoesPrevious() async {
        let (harness, first, _) = await playSecondOfTwo()
        harness.engine.currentTime = 3

        harness.playback.playPrevious()
        for _ in 0..<20 where harness.playback.currentSong?.id != first.id { await Task.yield() }

        #expect(harness.playback.currentSong?.id == first.id)
    }
}

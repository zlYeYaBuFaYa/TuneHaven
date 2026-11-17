import Testing
import Foundation
import AVFoundation
@testable import TuneHaven

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - 队列编辑与音乐库删除同步

@Suite("播放队列与删除同步")
@MainActor
struct PlaybackQueueSyncTests {

    private func songs(_ titles: [String]) -> [Song] {
        titles.map { makeFormatSong(format: "mp3", title: $0) }
    }

    /// 队列 [A, B, C]，从 A 开始播放
    private func playingHarness() async -> (PlaybackHarness, [Song]) {
        let harness = await makeHarness(premium: false)
        let list = songs(["A", "B", "C"])
        harness.songs.songs = list
        harness.playback.queue.replaceQueue(with: list, startAt: 0)
        await harness.playback.play(song: list[0], in: .queue)
        harness.engine.playCalled = false
        harness.engine.loadCalled = false
        return (harness, list)
    }

    @Test("播放中移除当前项：接着播放后一首")
    func testRemoveCurrentWhilePlaying() async {
        let (harness, list) = await playingHarness()

        harness.playback.removeFromQueue(at: [0])
        await waitUntil { harness.playback.currentSong?.id == list[1].id && harness.engine.playCalled }

        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.engine.playCalled)
        #expect(harness.playback.queue.currentItem?.song.id == list[1].id)
        #expect(harness.playback.queue.count == 2)
    }

    @Test("暂停中移除当前项：切到后一首并保持暂停")
    func testRemoveCurrentWhilePaused() async {
        let harness = await makeHarness(premium: false)
        let list = songs(["A", "B"])
        harness.songs.songs = list
        harness.playback.queue.replaceQueue(with: list, startAt: 0)
        await harness.playback.prepare(song: list[0], in: .queue)
        #expect(harness.playback.isPlaying == false)

        harness.playback.removeFromQueue(at: [0])
        await waitUntil { harness.playback.currentSong?.id == list[1].id }

        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.engine.playCalled == false)
    }

    @Test("移除队尾的当前项：停止并清空当前歌曲")
    func testRemoveLastCurrentStops() async {
        let (harness, list) = await playingHarness()
        harness.playback.queue.setCurrentIndex(to: 2)
        await harness.playback.play(song: list[2], in: .queue)

        harness.playback.removeFromQueue(at: [2])

        #expect(harness.playback.currentSong == nil)
        #expect(harness.playback.isPlaying == false)
        #expect(harness.engine.stopCalled)
        #expect(harness.nowPlaying.clearCalled)
    }

    @Test("移除非当前项：不影响当前播放，索引随之调整")
    func testRemoveNonCurrent() async {
        let (harness, list) = await playingHarness()
        harness.playback.queue.setCurrentIndex(to: 1)
        await harness.playback.play(song: list[1], in: .queue)
        harness.engine.loadCalled = false

        harness.playback.removeFromQueue(at: [0])

        #expect(harness.engine.loadCalled == false)
        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.playback.queue.currentIndex == 0)
        #expect(harness.playback.queue.currentItem?.song.id == list[1].id)
    }

    @Test("音乐库删除队列里的非当前歌曲：从队列消失")
    func testLibraryDeleteRemovesQueuedSong() async throws {
        let (harness, list) = await playingHarness()

        _ = try await harness.library.softDelete(songIds: [list[2].id])
        await waitUntil { harness.playback.queue.count == 2 }

        #expect(harness.playback.queue.queue.map(\.song.id) == [list[0].id, list[1].id])
        #expect(harness.playback.currentSong?.id == list[0].id)
    }

    @Test("音乐库删除当前歌曲：接着播放后一首，不被误停")
    func testLibraryDeleteCurrentPlaysNext() async throws {
        let (harness, list) = await playingHarness()

        _ = try await harness.library.softDelete(songIds: [list[0].id])
        await waitUntil { harness.playback.currentSong?.id == list[1].id && harness.engine.playCalled }

        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.playback.isPlaying)
        #expect(harness.playback.queue.queue.map(\.song.id) == [list[1].id, list[2].id])
    }

    @Test("当前歌曲不在队列里但被音乐库删除：停止并清空")
    func testLibraryDeleteCurrentNotInQueue() async throws {
        let harness = await makeHarness(premium: false)
        let song = makeFormatSong(format: "mp3", title: "A")
        harness.songs.songs = [song]
        await harness.playback.prepare(song: song, in: .queue)
        #expect(harness.playback.queue.count == 0)
        #expect(harness.playback.currentSong?.id == song.id)

        _ = try await harness.library.softDelete(songIds: [song.id])
        await waitUntil { harness.playback.currentSong == nil }

        #expect(harness.playback.currentSong == nil)
        #expect(harness.nowPlaying.clearCalled)
    }

    @Test("Free 用户移除当前项后，后一首是无损时停在该首并给出软墙信号")
    func testRemoveCurrentSuccessorLosslessBlocked() async {
        let harness = await makeHarness(premium: false)
        let mp3 = makeFormatSong(format: "mp3", title: "A")
        let flac = makeFormatSong(format: "flac", title: "B")
        harness.songs.songs = [mp3, flac]
        harness.playback.queue.replaceQueue(with: [mp3, flac], startAt: 0)
        await harness.playback.play(song: mp3, in: .queue)
        harness.engine.playCalled = false

        harness.playback.removeFromQueue(at: [0])

        #expect(harness.playback.currentSong?.id == flac.id)
        #expect(harness.playback.losslessBlockedSong?.id == flac.id)
        #expect(harness.engine.playCalled == false)
    }

    @Test("清空队列保留当前歌曲，播放不中断")
    func testClearQueueKeepsCurrent() async {
        let (harness, list) = await playingHarness()

        harness.playback.clearQueue()

        #expect(harness.playback.queue.queue.map(\.song.id) == [list[0].id])
        #expect(harness.playback.queue.currentIndex == 0)
        #expect(harness.engine.stopCalled == false)
        #expect(harness.playback.isPlaying)
    }

    @Test("只预备不播放时不激活音频会话")
    func testPrepareDoesNotActivateSession() async {
        let harness = await makeHarness(premium: false)
        let song = makeFormatSong(format: "mp3", title: "A")
        harness.songs.songs = [song]

        await harness.playback.prepare(song: song, in: .queue)

        #expect(harness.engine.loadCalled)
        #expect(harness.audioSession.ensureActiveCalled == false)
    }
}

// MARK: - AudioEngine：中断恢复与加载代次（真实单例）

@Suite("AudioEngine 中断与加载", .serialized)
@MainActor
struct AudioEngineBehaviorTests {

    private func postInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if type == .ended {
            let options: AVAudioSession.InterruptionOptions = shouldResume ? [.shouldResume] : []
            info[AVAudioSessionInterruptionOptionKey] = options.rawValue
        }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: info
        )
    }

    @Test("中断前已暂停：中断结束即使 shouldResume 也不恢复")
    func testInterruptionDoesNotResumeWhenPaused() async {
        let engine = AudioEngine.shared
        engine.stop()
        defer { engine.stop() }

        postInterruption(.began)
        try? await Task.sleep(for: .milliseconds(50))
        postInterruption(.ended, shouldResume: true)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(engine.isPlaying == false)
    }

    @Test("中断前在播放：中断结束且 shouldResume 时恢复")
    func testInterruptionResumesWhenPlaying() async {
        let engine = AudioEngine.shared
        engine.stop()
        defer { engine.stop() }
        engine.play()
        #expect(engine.isPlaying)

        postInterruption(.began)
        await waitUntil { !engine.isPlaying }
        #expect(engine.isPlaying == false)
        postInterruption(.ended, shouldResume: true)
        await waitUntil { engine.isPlaying }

        #expect(engine.isPlaying)
    }

    @Test("先发起的加载更晚完成时，不会把当前 item 换回旧歌")
    func testSlowEarlierLoadIsDiscarded() async throws {
        let source = try #require(Bundle(for: EngineTestBundleToken.self).url(forResource: "sine-2s", withExtension: "mp3"))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioEngineSlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let slow = dir.appendingPathComponent("slow.mp3")
        let fast = dir.appendingPathComponent("fast.mp3")
        try FileManager.default.copyItem(at: source, to: slow)
        try FileManager.default.copyItem(at: source, to: fast)
        let engine = AudioEngine.shared
        engine.beforeAssetLoadForTesting = { url in
            if url.lastPathComponent == "slow.mp3" {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer {
            engine.beforeAssetLoadForTesting = nil
            engine.stop()
        }

        let first = Task { await engine.load(url: slow) }
        await Task.yield()
        let second = Task { await engine.load(url: fast) }
        await second.value
        await first.value

        #expect(engine.currentItemURL?.standardizedFileURL == fast.standardizedFileURL)
    }
}

private final class EngineTestBundleToken {}

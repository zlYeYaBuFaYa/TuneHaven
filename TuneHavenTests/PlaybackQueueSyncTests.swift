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

// MARK: - 队列编辑与音乐库删除同步（交互设计 §7.5）

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

    private func finishCurrentSong(_ harness: PlaybackHarness) {
        harness.engine.playbackEndedSubject.send()
    }

    @Test("移除当前项不切断音频：进入队列外播放，播完从原后继项继续")
    func testRemoveCurrentContinuesThenSuccessor() async {
        let (harness, list) = await playingHarness()

        harness.playback.removeFromQueue(at: [0])

        #expect(harness.engine.loadCalled == false)
        #expect(harness.engine.stopCalled == false)
        #expect(harness.playback.currentSong?.id == list[0].id)
        #expect(harness.playback.isPlayingOutsideQueue)
        #expect(harness.playback.queue.currentIndex == nil)
        #expect(harness.playback.queue.queue.map(\.song.id) == [list[1].id, list[2].id])

        finishCurrentSong(harness)
        await waitUntil { harness.playback.currentSong?.id == list[1].id && harness.engine.playCalled }

        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.playback.queue.currentItem?.song.id == list[1].id)
        #expect(harness.playback.isPlayingOutsideQueue == false)
    }

    @Test("移除队尾的当前项：播完后停止，不清空当前歌曲")
    func testRemoveLastCurrentStopsAfterEnd() async {
        let (harness, list) = await playingHarness()
        harness.playback.queue.setCurrentIndex(to: 2)
        await harness.playback.play(song: list[2], in: .queue)

        harness.playback.removeFromQueue(at: [2])
        #expect(harness.playback.isPlayingOutsideQueue)
        #expect(harness.engine.stopCalled == false)

        finishCurrentSong(harness)
        await waitUntil { harness.engine.stopCalled }

        #expect(harness.engine.stopCalled)
        #expect(harness.playback.isPlaying == false)
        #expect(harness.playback.currentSong?.id == list[2].id)
        #expect(harness.playback.isPlayingOutsideQueue == false)
    }

    @Test("队列外播放期间原后继项也被移除：后继顺延")
    func testSuccessorRemovedShiftsForward() async {
        let (harness, list) = await playingHarness()
        harness.playback.removeFromQueue(at: [0])   // 后继为 B，队列 [B, C]

        harness.playback.removeFromQueue(at: [0])   // 再移除 B
        finishCurrentSong(harness)
        await waitUntil { harness.playback.currentSong?.id == list[2].id }

        #expect(harness.playback.currentSong?.id == list[2].id)
    }

    @Test("Free 用户队列外播放结束、后继为无损：停在该首并给出软墙信号")
    func testSuccessorLosslessBlocked() async {
        let harness = await makeHarness(premium: false)
        let mp3 = makeFormatSong(format: "mp3", title: "A")
        let flac = makeFormatSong(format: "flac", title: "B")
        harness.songs.songs = [mp3, flac]
        harness.playback.queue.replaceQueue(with: [mp3, flac], startAt: 0)
        await harness.playback.play(song: mp3, in: .queue)
        harness.engine.playCalled = false

        harness.playback.removeFromQueue(at: [0])
        finishCurrentSong(harness)
        await waitUntil { harness.playback.losslessBlockedSong != nil }

        #expect(harness.playback.currentSong?.id == flac.id)
        #expect(harness.playback.losslessBlockedSong?.id == flac.id)
        #expect(harness.engine.playCalled == false)
    }

    @Test("队列外播放时点播队列中的歌曲：退出队列外状态")
    func testPlayingQueueItemExitsOutOfQueue() async {
        let (harness, list) = await playingHarness()
        harness.playback.removeFromQueue(at: [0])

        harness.playback.queue.setCurrentIndex(to: 1)
        await harness.playback.play(song: list[2], in: .queue)

        #expect(harness.playback.isPlayingOutsideQueue == false)
        #expect(harness.playback.currentSong?.id == list[2].id)
    }

    @Test("移除非当前项：不影响当前播放，索引随之调整")
    func testRemoveNonCurrent() async {
        let (harness, list) = await playingHarness()
        harness.playback.queue.setCurrentIndex(to: 1)
        await harness.playback.play(song: list[1], in: .queue)
        harness.engine.loadCalled = false

        harness.playback.removeFromQueue(at: [0])

        #expect(harness.engine.loadCalled == false)
        #expect(harness.playback.isPlayingOutsideQueue == false)
        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.playback.queue.currentIndex == 0)
        #expect(harness.playback.queue.currentItem?.song.id == list[1].id)
    }

    @Test("清空队列：队列为空，当前音频继续，播完后停止")
    func testClearQueue() async {
        let (harness, list) = await playingHarness()

        harness.playback.clearQueue()

        #expect(harness.playback.queue.count == 0)
        #expect(harness.engine.stopCalled == false)
        #expect(harness.playback.isPlaying)
        #expect(harness.playback.currentSong?.id == list[0].id)

        finishCurrentSong(harness)
        await waitUntil { harness.engine.stopCalled }

        #expect(harness.playback.isPlaying == false)
        #expect(harness.playback.queue.count == 0)
    }

    @Test("音乐库删除队列里的非当前歌曲：从队列消失")
    func testLibraryDeleteRemovesQueuedSong() async throws {
        let (harness, list) = await playingHarness()

        _ = try await harness.library.softDelete(songIds: [list[2].id])
        await waitUntil { harness.playback.queue.count == 2 }

        #expect(harness.playback.queue.queue.map(\.song.id) == [list[0].id, list[1].id])
        #expect(harness.playback.currentSong?.id == list[0].id)
    }

    @Test("音乐库删除正在播放的歌曲：文件已移走，立即播放后一首")
    func testLibraryDeleteCurrentPlaysNext() async throws {
        let (harness, list) = await playingHarness()

        _ = try await harness.library.softDelete(songIds: [list[0].id])
        await waitUntil { harness.playback.currentSong?.id == list[1].id && harness.engine.playCalled }

        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.playback.isPlaying)
        #expect(harness.playback.queue.queue.map(\.song.id) == [list[1].id, list[2].id])
    }

    @Test("队列外播放的歌曲被音乐库删除：立即播放原后继项")
    func testLibraryDeleteOutOfQueueSong() async throws {
        let (harness, list) = await playingHarness()
        harness.playback.removeFromQueue(at: [0])

        _ = try await harness.library.softDelete(songIds: [list[0].id])
        await waitUntil { harness.playback.currentSong?.id == list[1].id && harness.engine.playCalled }

        #expect(harness.playback.currentSong?.id == list[1].id)
        #expect(harness.playback.isPlayingOutsideQueue == false)
    }

    @Test("当前歌曲不在队列里但被音乐库删除：停止并清空")
    func testLibraryDeleteCurrentNotInQueue() async throws {
        let harness = await makeHarness(premium: false)
        let song = makeFormatSong(format: "mp3", title: "A")
        harness.songs.songs = [song]
        await harness.playback.prepare(song: song, in: .queue)
        #expect(harness.playback.queue.count == 0)

        _ = try await harness.library.softDelete(songIds: [song.id])
        await waitUntil { harness.playback.currentSong == nil }

        #expect(harness.playback.currentSong == nil)
        #expect(harness.nowPlaying.clearCalled)
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

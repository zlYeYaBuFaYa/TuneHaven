// 命名约定：P0 = 阻塞级修复（崩溃/数据丢失），P1 = 重要级修复（功能缺陷），P2 = 建议级修复（体验优化）
// TODO: 长期重构 - 按功能模块重组测试文件，而非按修复优先级命名

import Testing
import Foundation
@testable import TuneHaven

// Tests for: PlayQueueService（moveInQueue / 空队列边界）, SearchDebouncer, ThemeVisualConfig / ThemeRegistry, 历史 P1 修复回归

// MARK: - #11 moveInQueue currentIndex 同步

@Suite("P1 Fix #11: moveInQueue currentIndex 同步")
struct MoveInQueueIndexSyncTests {

    @Test("移动歌曲后 currentIndex 跟随当前播放歌曲", .serialized)
    @MainActor func testMoveCurrentSongKeepsIndex() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 1)

        #expect(service.currentItem?.song.title == "B")

        service.moveInQueue(from: IndexSet([1]), to: 0)

        #expect(service.currentItem?.song.title == "B")
        #expect(service.currentIndex == 0)
    }

    @Test("移动非当前歌曲后 currentIndex 仍指向正确歌曲", .serialized)
    @MainActor func testMoveOtherSongKeepsCurrent() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        #expect(service.currentItem?.song.title == "A")

        service.moveInQueue(from: IndexSet([2]), to: 0)

        #expect(service.currentItem?.song.title == "A")
    }

    @Test("移动到末尾后 currentIndex 正确", .serialized)
    @MainActor func testMoveCurrentToEnd() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        service.moveInQueue(from: IndexSet([0]), to: 3)

        #expect(service.currentItem?.song.title == "A")
        #expect(service.currentIndex == 2)
    }
}

// MARK: - #17 SearchDebouncer 在 ViewModel 中正确工作

@Suite("P1 Fix #17: SearchDebouncer 稳定性")
struct SearchDebouncerTests {

    // debounce 间隔 ~300ms；初始等待 1s 覆盖 debounce + Combine 调度延迟，
    // 之后用 polling + deadline 容忍 CI 负载抖动，避免固定 sleep 导致的 flaky test。

    @Test("SearchDebouncer 发送值后 debouncedQuery 更新", .serialized, .timeLimit(.seconds(8)))
    @MainActor func testDebouncerUpdatesQuery() async throws {
        let debouncer = SearchDebouncer()
        debouncer.send("test")

        try await Task.sleep(for: .milliseconds(1000))

        let deadline = ContinuousClock.now + .seconds(5)
        while debouncer.debouncedQuery != "test" && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(150))
        }

        #expect(debouncer.debouncedQuery == "test")
    }

    @Test("SearchDebouncer 快速连续发送只保留最后一个值", .serialized, .timeLimit(.seconds(8)))
    @MainActor func testDebouncerDeduplicates() async throws {
        let debouncer = SearchDebouncer()
        debouncer.send("a")
        debouncer.send("ab")
        debouncer.send("abc")

        try await Task.sleep(for: .milliseconds(1000))

        let deadline = ContinuousClock.now + .seconds(5)
        while debouncer.debouncedQuery != "abc" && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(150))
        }

        #expect(debouncer.debouncedQuery == "abc")
    }
}

// MARK: - #19 ThemeVisualConfig 映射正确性（UI 重设计后适配 4 套新主题）

@Suite("P1 Fix #19: ThemeVisualConfig 映射")
struct ThemeVisualConfigTests {

    init() {
        ThemeRegistry.shared.reset()
        ThemeRegistry.shared.bootstrap()
    }

    @Test("素云白简使用 solidColor + softFloat 配置")
    func testCloudWhiteConfig() {
        let style = ThemeStyle.cloudWhite
        #expect(style.visualConfig.backgroundType == .solidColor)
        #expect(style.visualConfig.cardStyle == .softFloat)
        #expect(style.hasCustomBackground == false)
    }

    @Test("星际穹顶使用 cosmicParticles + glassmorphism")
    func testCosmicTechConfig() {
        let style = ThemeStyle.cosmicTech
        #expect(style.visualConfig.backgroundType == .codeGenerated(.cosmicParticles))
        #expect(style.visualConfig.cardStyle == .glassmorphism)
        #expect(style.hasCustomBackground == true)
    }

    @Test("暮光玫瑰使用 glassmorphism 卡片风格")
    func testTwilightRoseConfig() {
        let style = ThemeStyle.twilightRose
        #expect(style.visualConfig.cardStyle == .glassmorphism)
        #expect(style.visualConfig.navigationBarBlur == true)
    }

    @Test("所有新主题都已在 ThemeRegistry 注册")
    func testAllNewThemesRegistered() {
        let themes = ThemeRegistry.shared.allThemes
        #expect(themes.count == 4)
        let ids = Set(themes.map { $0.id })
        #expect(ids.contains("cloud_white"))
        #expect(ids.contains("azure_sky"))
        #expect(ids.contains("twilight_rose"))
        #expect(ids.contains("cosmic_tech"))
    }
}

// MARK: - #15 删除歌单清理关联 (逻辑验证)

@Suite("P1 Fix: PlayQueueService 边界条件")
struct PlayQueueEdgeCaseTests {

    @Test("repeatAll 空队列时返回 nil 不崩溃", .serialized)
    @MainActor func testRepeatAllEmptyQueue() {
        let service = PlayQueueService()
        let next = service.nextSong(for: .repeatAll, dislikes: [:])
        #expect(next == nil)
    }

    @Test("shuffle 空队列时返回 nil 不崩溃", .serialized)
    @MainActor func testShuffleEmptyQueue() {
        let service = PlayQueueService()
        let next = service.nextSong(for: .shuffle, dislikes: [:])
        #expect(next == nil)
    }

    @Test("moveInQueue 无 currentIndex 时不崩溃", .serialized)
    @MainActor func testMoveInQueueNoCurrent() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B")]
        _ = service.appendToQueue(songs)

        service.moveInQueue(from: IndexSet([0]), to: 2)
        #expect(service.queue[0].song.title == "B")
        #expect(service.queue[1].song.title == "A")
        #expect(service.currentIndex == nil)
    }
}

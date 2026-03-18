import Testing
import Foundation
@testable import music_demo

// MARK: - Test Helpers

private func makeSong(
    id: UUID = UUID(),
    title: String = "Test Song",
    artist: String = "Test Artist",
    album: String = "Test Album"
) -> Song {
    Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: 180,
        fileHash: UUID().uuidString,
        fileRelativePath: "test.mp3",
        coverImagePath: nil,
        lyricsPath: nil,
        lyricsSource: nil,
        metadata: Metadata(
            format: "mp3", sampleRate: 44100, bitRate: 320, channels: 2,
            encoder: nil, trackNumber: nil, year: 2024, genre: nil
        ),
        importDate: Date(),
        fileSize: 1024 * 1024,
        playCount: 0,
        isFavorite: false,
        favoriteDate: nil,
        lastPlayedDate: nil
    )
}

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

    @Test("SearchDebouncer 发送值后 debouncedQuery 更新", .serialized)
    @MainActor func testDebouncerUpdatesQuery() async throws {
        let debouncer = SearchDebouncer()
        debouncer.send("test")

        try await Task.sleep(for: .milliseconds(400))

        #expect(debouncer.debouncedQuery == "test")
    }

    @Test("SearchDebouncer 快速连续发送只保留最后一个值", .serialized)
    @MainActor func testDebouncerDeduplicates() async throws {
        let debouncer = SearchDebouncer()
        debouncer.send("a")
        debouncer.send("ab")
        debouncer.send("abc")

        try await Task.sleep(for: .milliseconds(400))

        #expect(debouncer.debouncedQuery == "abc")
    }
}

// MARK: - #19 ThemeVisualConfig 映射正确性

@Suite("P1 Fix #19: ThemeVisualConfig 映射")
struct ThemeVisualConfigTests {

    @Test("漫彩波普使用 comicPop 配置")
    func testComicPopConfig() {
        let style = ThemeStyle.comicPop
        let config = style.visualConfig
        #expect(config.backgroundType == .codeGenerated(.comicSky))
        #expect(config.cardStyle == .rounded)
        #expect(config.fontStyle == .rounded)
        #expect(style.hasCustomBackground == true)
    }

    @Test("赤焰科技使用 crimsonTech 配置")
    func testCrimsonTechConfig() {
        let style = ThemeStyle.crimsonTech
        let config = style.visualConfig
        #expect(config.backgroundType == .codeGenerated(.techGrid))
        #expect(config.cardStyle == .glassmorphism)
        #expect(config.fontStyle == .monospaced)
        #expect(style.hasCustomBackground == true)
    }

    @Test("水墨丹青使用 inkWash 配置")
    func testInkWashConfig() {
        let style = ThemeStyle.inkWash
        let config = style.visualConfig
        #expect(config.backgroundType == .codeGenerated(.inkMountain))
        #expect(config.cardStyle == .minimal)
        #expect(config.fontStyle == .serif)
        #expect(style.hasCustomBackground == true)
    }

    @Test("玫瑰梦境使用 roseDream 配置")
    func testRoseDreamConfig() {
        let style = ThemeStyle.roseDream
        let config = style.visualConfig
        #expect(config.backgroundType == .codeGenerated(.rosePetal))
        #expect(config.cardStyle == .softFloat)
        #expect(style.hasCustomBackground == true)
    }

    @Test("霜色风雅使用 frostElegance 配置")
    func testFrostEleganceConfig() {
        let style = ThemeStyle.frostElegance
        let config = style.visualConfig
        #expect(config.backgroundType == .codeGenerated(.frostAurora))
        #expect(config.cardStyle == .frosted)
        #expect(style.hasCustomBackground == true)
    }

    @Test("翠野清风使用纯色默认配置")
    func testMeadowBreezeConfig() {
        let style = ThemeStyle.meadowBreeze
        let config = style.visualConfig
        #expect(config.backgroundType == .solidColor)
        #expect(config.cardStyle == .standard)
        #expect(style.hasCustomBackground == false)
    }

    @Test("所有主题都已在 ThemeRegistry 注册")
    func testAllThemesRegistered() {
        let registry = ThemeRegistry.shared
        registry.bootstrap()
        let themes = registry.allThemes
        #expect(themes.count >= 6)
        let ids = Set(themes.map { $0.id })
        #expect(ids.contains("meadow_breeze"))
        #expect(ids.contains("rose_dream"))
        #expect(ids.contains("frost_elegance"))
        #expect(ids.contains("crimson_tech"))
        #expect(ids.contains("comic_pop"))
        #expect(ids.contains("ink_wash"))
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

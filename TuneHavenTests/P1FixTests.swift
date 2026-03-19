import Testing
import Foundation
@testable import TuneHaven

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

// MARK: - #19 ThemeVisualConfig 映射正确性（重构后适配新主题）

@Suite("P1 Fix #19: ThemeVisualConfig 映射")
struct ThemeVisualConfigTests {

    init() {
        ThemeRegistry.shared.reset()
        ThemeRegistry.shared.bootstrap()
    }

    @Test("青云薄荷使用 mintLeaves 配置")
    func testMintBreezeConfig() {
        let style = ThemeStyle.mintBreeze
        #expect(style.visualConfig.backgroundType == .codeGenerated(.mintLeaves))
        #expect(style.visualConfig.cardStyle == .minimal)
        #expect(style.hasCustomBackground == true)
    }

    @Test("赛博霓虹使用 cyberParticles + monospaced")
    func testCyberNeonConfig() {
        let style = ThemeStyle.cyberNeon
        #expect(style.visualConfig.backgroundType == .codeGenerated(.cyberParticles))
        #expect(style.visualConfig.cardStyle == .glassmorphism)
        #expect(style.visualConfig.fontStyle == .monospaced)
    }

    @Test("冰川幽蓝使用 frosted 卡片风格")
    func testGlacierBlueConfig() {
        let style = ThemeStyle.glacierBlue
        #expect(style.visualConfig.cardStyle == .frosted)
        #expect(style.visualConfig.navigationBarBlur == true)
    }

    @Test("所有新主题都已在 ThemeRegistry 注册")
    func testAllNewThemesRegistered() {
        let themes = ThemeRegistry.shared.allThemes
        #expect(themes.count == 6)
        let ids = Set(themes.map { $0.id })
        #expect(ids.contains("mint_breeze"))
        #expect(ids.contains("deep_ocean"))
        #expect(ids.contains("cyber_neon"))
        #expect(ids.contains("glacier_blue"))
        #expect(ids.contains("aurora_dream"))
        #expect(ids.contains("midnight_gold"))
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

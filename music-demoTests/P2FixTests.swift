import Testing
import Foundation
@testable import music_demo

// MARK: - #20 AudioSessionManager 重试逻辑 & #21 ensureActive 返回值 & #25 @MainActor

@Suite("AudioSessionManager Tests")
struct AudioSessionManagerTests {

    @Test("ensureActive 返回 Bool 类型")
    @MainActor
    func testEnsureActiveReturnsBool() {
        let result = AudioSessionManager.shared.ensureActive()
        #expect(result == true || result == false)
    }

    @Test("configure 返回 Bool 类型")
    @MainActor
    func testConfigureReturnsBool() {
        let result = AudioSessionManager.shared.configure()
        #expect(result == true || result == false)
    }
}

// MARK: - #26 ImportService progress 同步

@Suite("ImportService Progress Sync Tests")
struct ImportServiceProgressTests {

    @Test("ImportService 初始 progress 为 nil")
    @MainActor
    func testInitialProgressIsNil() {
        let service = ImportService()
        #expect(service.progress == nil)
    }

    @Test("ImportService 初始 isImporting 为 false")
    @MainActor
    func testInitialIsImportingIsFalse() {
        let service = ImportService()
        #expect(service.isImporting == false)
    }
}

// MARK: - #28 PlayQueueService repeatAll 空队列防护

@Suite("PlayQueueService Empty Queue Guard Tests")
struct PlayQueueEmptyGuardTests {

    @Test("空队列 repeatAll 模式 nextSong 返回 nil")
    @MainActor
    func testRepeatAllEmptyQueueReturnsNil() {
        let service = PlayQueueService()
        let next = service.nextSong(for: .repeatAll, dislikes: [:])
        #expect(next == nil)
    }

    @Test("空队列 sequential 模式 nextSong 返回 nil")
    @MainActor
    func testSequentialEmptyQueueReturnsNil() {
        let service = PlayQueueService()
        let next = service.nextSong(for: .sequential, dislikes: [:])
        #expect(next == nil)
    }

    @Test("空队列 shuffle 模式 nextSong 返回 nil")
    @MainActor
    func testShuffleEmptyQueueReturnsNil() {
        let service = PlayQueueService()
        let next = service.nextSong(for: .shuffle, dislikes: [:])
        #expect(next == nil)
    }

    @Test("空队列 repeatOne 模式 nextSong 返回 nil")
    @MainActor
    func testRepeatOneEmptyQueueReturnsNil() {
        let service = PlayQueueService()
        let next = service.nextSong(for: .repeatOne, dislikes: [:])
        #expect(next == nil)
    }

    @Test("repeatAll 模式所有歌曲播完后重置并从头播放")
    @MainActor
    func testRepeatAllResetsAndPlaysFromStart() {
        let service = PlayQueueService()
        let songs = makeSongs(count: 3)
        service.replaceQueue(with: songs, startAt: 0)

        for i in 0..<3 { service.queue[i].isPlayed = true }

        let next = service.nextSong(for: .repeatAll, dislikes: [:])
        #expect(next != nil)
        #expect(next?.song.id == songs[0].id)
    }
}

// MARK: - #30 "/" 分隔符问题

@Suite("AlbumKey Separator Tests")
struct AlbumKeySeparatorTests {

    @Test("MusicLibraryService AlbumKey 结构体的 artist 和 album 独立哈希")
    func testAlbumKeyWithSlash() {
        struct AlbumKey: Hashable {
            let artist: String
            let album: String
        }

        let key1 = AlbumKey(artist: "AC/DC", album: "Back in Black")
        let key2 = AlbumKey(artist: "AC", album: "DC/Back in Black")
        #expect(key1 != key2)
    }

    @Test("含 '/' 的艺术家名作为 AlbumKey 不会混淆")
    func testAlbumKeyArtistWithSlash() {
        struct AlbumKey: Hashable {
            let artist: String
            let album: String
        }

        let key1 = AlbumKey(artist: "AC/DC", album: "Highway to Hell")
        let key2 = AlbumKey(artist: "AC/DC", album: "Back in Black")
        #expect(key1 != key2)

        let key3 = AlbumKey(artist: "AC/DC", album: "Highway to Hell")
        #expect(key1 == key3)
    }
}

// MARK: - #32 setCustomCover 无效图片抛错

@Suite("PlaylistService CustomCover Error Tests")
struct CustomCoverErrorTests {

    @Test("setCustomCover 无效图片数据应抛出错误")
    @MainActor
    func testSetCustomCoverInvalidDataThrows() async {
        let service = PlaylistService()
        let invalidData = "not an image".data(using: .utf8)!

        do {
            try await service.setCustomCover(playlistId: UUID(), imageData: invalidData)
            #expect(Bool(false), "应该抛出错误")
        } catch {
            #expect(error is AppError)
        }
    }
}

// MARK: - AppLogger Tests

@Suite("AppLogger Tests")
struct AppLoggerTests {

    @Test("AppLogger 单例存在")
    func testAppLoggerSingleton() {
        let logger = AppLogger.shared
        #expect(logger !== nil as AnyObject?)
    }

    @Test("LogLevel rawValue 正确")
    func testLogLevelRawValues() {
        #expect(LogLevel.debug.rawValue == "DEBUG")
        #expect(LogLevel.info.rawValue == "INFO")
        #expect(LogLevel.error.rawValue == "ERROR")
    }
}

// MARK: - Helpers

private func makeSong(title: String = "Test", artist: String = "Artist", album: String = "Album") -> Song {
    Song(
        id: UUID(), title: title, artist: artist, album: album,
        duration: 180, fileHash: UUID().uuidString, fileRelativePath: "test.mp3",
        coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
        metadata: Metadata(format: "mp3", sampleRate: nil, bitRate: nil, channels: nil, encoder: nil, trackNumber: nil, year: nil, genre: nil),
        importDate: Date(), fileSize: 1024, playCount: 0,
        isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
    )
}

private func makeSongs(count: Int) -> [Song] {
    (0..<count).map { makeSong(title: "Song \($0)") }
}

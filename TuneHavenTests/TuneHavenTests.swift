import Testing
import Foundation
@testable import TuneHaven

// MARK: - Test Suite Overview
//
// 本项目单元测试覆盖以下模块：
//
// ┌─────────────────────────────────────────────────────────────┐
// │  测试文件                    覆盖模块                         │
// ├─────────────────────────────────────────────────────────────┤
// │  PlayQueueServiceTests      播放队列核心逻辑                  │
// │  SearchServiceTests         搜索逻辑（前缀匹配/分组）          │
// │  LyricsServiceTests         LRC 歌词解析                     │
// │  AppErrorTests              错误码和错误描述                   │
// │  FileStorageServiceTests    文件格式校验/SHA256/沙盒路径       │
// │  MusicLibraryServiceTests   艺术家/专辑分组/枚举               │
// │  PlaylistServiceTests       歌单命名校验/实体/PagedResult      │
// └─────────────────────────────────────────────────────────────┘

@Suite("TuneHaven 集成验证")
struct TuneHavenTests {

    // MARK: - 基础模型验证

    @Test("Song 模型 Equatable：属性不同则不相等，属性相同则相等")
    func testSongEquality() {
        let id = UUID()
        let now = Date()
        let metadata = Metadata(
            format: "mp3", sampleRate: 44100, bitRate: 320,
            channels: 2, encoder: nil, trackNumber: nil, year: nil, genre: nil
        )
        let s1 = Song(
            id: id, title: "夜曲", artist: "周杰伦", album: "十一月的萧邦",
            duration: 227, fileHash: "abc123", fileRelativePath: "abc123_夜曲.mp3",
            coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
            metadata: metadata, importDate: now, fileSize: 8 * 1024 * 1024,
            playCount: 0, isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
        )
        let s2 = Song(
            id: id, title: "晴天", artist: "周杰伦", album: "叶惠美",
            duration: 269, fileHash: "def456", fileRelativePath: "def456_晴天.mp3",
            coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
            metadata: metadata, importDate: now, fileSize: 7 * 1024 * 1024,
            playCount: 0, isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
        )
        let s3 = Song(
            id: id, title: "夜曲", artist: "周杰伦", album: "十一月的萧邦",
            duration: 227, fileHash: "abc123", fileRelativePath: "abc123_夜曲.mp3",
            coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
            metadata: metadata, importDate: now, fileSize: 8 * 1024 * 1024,
            playCount: 0, isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
        )
        #expect(s1 != s2, "仅 id 相同但属性不同，合成 Equatable 应不相等")
        #expect(s1 == s3, "所有属性相同应相等")
    }

    @Test("Song 模型 Hashable：不同 id 产生不同哈希")
    func testSongHashable() {
        let metadata = Metadata(
            format: "mp3", sampleRate: nil, bitRate: nil,
            channels: nil, encoder: nil, trackNumber: nil, year: nil, genre: nil
        )
        let songs = (0..<10).map { _ -> Song in
            Song(
                id: UUID(), title: "T", artist: "A", album: "B",
                duration: 180, fileHash: UUID().uuidString, fileRelativePath: "test.mp3",
                coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
                metadata: metadata, importDate: Date(), fileSize: 1024,
                playCount: 0, isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
            )
        }
        let set = Set(songs)
        #expect(set.count == 10) // 10 首不同歌曲，集合大小为 10
    }

    @Test("LyricsSource rawValue 映射正确")
    func testLyricsSourceRawValues() {
        #expect(LyricsSource.embedded.rawValue == 0)
        #expect(LyricsSource.file.rawValue == 1)
        #expect(LyricsSource.manual.rawValue == 2)
    }

    @Test("QueueItem 初始化时 isPlayed 默认为 false")
    func testQueueItemDefaultNotPlayed() {
        let song = Song(
            id: UUID(), title: "T", artist: "A", album: "B",
            duration: 180, fileHash: "hash", fileRelativePath: "test.mp3",
            coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
            metadata: Metadata(format: "mp3", sampleRate: nil, bitRate: nil, channels: nil, encoder: nil, trackNumber: nil, year: nil, genre: nil),
            importDate: Date(), fileSize: 1024, playCount: 0,
            isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
        )
        let item = QueueItem(song: song)
        #expect(!item.isPlayed)
    }

    @Test("QueueItem isPlayed 可以被标记为 true")
    func testQueueItemCanBeMarkedAsPlayed() {
        let song = Song(
            id: UUID(), title: "T", artist: "A", album: "B",
            duration: 180, fileHash: "hash", fileRelativePath: "test.mp3",
            coverImagePath: nil, lyricsPath: nil, lyricsSource: nil,
            metadata: Metadata(format: "mp3", sampleRate: nil, bitRate: nil, channels: nil, encoder: nil, trackNumber: nil, year: nil, genre: nil),
            importDate: Date(), fileSize: 1024, playCount: 0,
            isFavorite: false, favoriteDate: nil, lastPlayedDate: nil
        )
        var item = QueueItem(song: song)
        item.isPlayed = true
        #expect(item.isPlayed)
    }

    @Test("PlayQueueConstants 最大容量为 999")
    func testQueueMaxCapacity() {
        #expect(PlayQueueConstants.maxCount == 999)
    }

    @Test("LyricsLine 初始化时自动生成唯一 id")
    func testLyricsLineAutoId() {
        let line1 = LyricsLine(timestamp: 10.0, text: "行一")
        let line2 = LyricsLine(timestamp: 20.0, text: "行二")
        #expect(line1.id != line2.id)
    }

    @Test("Metadata 结构体包含所有必要字段")
    func testMetadataFields() {
        let meta = Metadata(
            format: "flac",
            sampleRate: 96000,
            bitRate: 1411,
            channels: 2,
            encoder: "FLAC 1.3.4",
            trackNumber: 5,
            year: 2023,
            genre: "Classical"
        )
        #expect(meta.format == "flac")
        #expect(meta.sampleRate == 96000)
        #expect(meta.bitRate == 1411)
        #expect(meta.channels == 2)
        #expect(meta.encoder == "FLAC 1.3.4")
        #expect(meta.trackNumber == 5)
        #expect(meta.year == 2023)
        #expect(meta.genre == "Classical")
    }
}

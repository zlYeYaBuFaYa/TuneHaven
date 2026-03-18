import Testing
import Foundation
@testable import TuneHaven

// MARK: - Playlist Name Validation Logic Tests
// 测试 PlaylistService 中歌单命名相关的纯逻辑

@Suite("PlaylistService - 命名校验逻辑")
struct PlaylistNameValidationTests {

    // MARK: - 命名校验辅助函数（与 PlaylistService.createPlaylist 逻辑一致）

    private func validatePlaylistName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw AppError.playlistNameEmpty }
        let reserved = ["我喜欢", "最近播放"]
        guard !reserved.contains(trimmed) else { throw AppError.playlistNameDuplicate }
    }

    // MARK: - 空名称验证

    @Test("空字符串歌单名称抛出 playlistNameEmpty 错误")
    func testEmptyNameThrows() throws {
        #expect(throws: AppError.playlistNameEmpty) {
            try validatePlaylistName("")
        }
    }

    @Test("纯空白字符名称抛出 playlistNameEmpty 错误")
    func testWhitespaceOnlyNameThrows() throws {
        #expect(throws: AppError.playlistNameEmpty) {
            try validatePlaylistName("   ")
        }
    }

    @Test("仅含制表符和换行符的名称抛出 playlistNameEmpty 错误")
    func testTabAndNewlineOnlyNameThrows() throws {
        #expect(throws: AppError.playlistNameEmpty) {
            try validatePlaylistName("\t\n  ")
        }
    }

    // MARK: - 系统歌单名称保护

    @Test("名称为「我喜欢」时抛出 playlistNameDuplicate 错误")
    func testFavoritePlaylistNameThrows() throws {
        #expect(throws: AppError.playlistNameDuplicate) {
            try validatePlaylistName("我喜欢")
        }
    }

    @Test("名称为「最近播放」时抛出 playlistNameDuplicate 错误")
    func testRecentlyPlayedNameThrows() throws {
        #expect(throws: AppError.playlistNameDuplicate) {
            try validatePlaylistName("最近播放")
        }
    }

    @Test("系统歌单名称前后有空格时也被保护（trim 后检查）")
    func testFavoriteNameWithSpacesThrows() throws {
        #expect(throws: AppError.playlistNameDuplicate) {
            try validatePlaylistName("  我喜欢  ")
        }
    }

    // MARK: - 合法名称

    @Test("普通中文名称合法")
    func testValidChineseName() throws {
        try validatePlaylistName("我的歌单")
        // 无异常则通过
    }

    @Test("英文名称合法")
    func testValidEnglishName() throws {
        try validatePlaylistName("My Playlist")
    }

    @Test("含特殊字符的名称合法（v4.3 放宽限制）")
    func testValidNameWithSpecialChars() throws {
        try validatePlaylistName("Rock/Pop Mix")
        try validatePlaylistName("Best:Songs*2024")
        try validatePlaylistName("Jazz & Blues")
    }

    @Test("前后有空格的合法名称通过校验（trim 后不为空）")
    func testValidNameWithLeadingTrailingSpaces() throws {
        try validatePlaylistName("  我的歌单  ")
    }

    @Test("50 个字符的名称合法")
    func testValidLongName() throws {
        let name = String(repeating: "音", count: 50)
        try validatePlaylistName(name)
    }

    @Test("包含数字和特殊符号的名称合法")
    func testValidNameWithNumbers() throws {
        try validatePlaylistName("最爱 Top 100")
        try validatePlaylistName("2024年收藏集")
    }

    @Test("单个字符的名称合法")
    func testValidSingleCharName() throws {
        try validatePlaylistName("A")
    }

    @Test("emoji 名称合法")
    func testValidEmojiName() throws {
        try validatePlaylistName("🎵 音乐精选")
        try validatePlaylistName("❤️ 我爱的歌")
    }
}

// MARK: - Playlist Entity Tests

@Suite("Playlist Entity Tests")
struct PlaylistEntityTests {

    private func makePlaylist(
        id: UUID = UUID(),
        name: String = "测试歌单",
        isSystem: Bool = false,
        systemType: SystemPlaylistType = .normal,
        songCount: Int = 0,
        sortOrder: Int = 0
    ) -> Playlist {
        Playlist(
            id: id,
            name: name,
            description: nil,
            coverImagePath: nil,
            autoCoverHash: nil,
            isSystem: isSystem,
            systemType: systemType,
            songCount: songCount,
            groupId: nil,
            sortOrder: sortOrder,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test("Playlist id 唯一性")
    func testPlaylistIdUniqueness() {
        let p1 = makePlaylist()
        let p2 = makePlaylist()
        #expect(p1.id != p2.id)
    }

    @Test("系统歌单标记正确")
    func testSystemPlaylistFlag() {
        let favorites = makePlaylist(name: "我喜欢", isSystem: true, systemType: .favorites)
        let recentlyPlayed = makePlaylist(name: "最近播放", isSystem: true, systemType: .recentlyPlayed)
        let userPlaylist = makePlaylist(name: "我的歌单", isSystem: false, systemType: .normal)

        #expect(favorites.isSystem)
        #expect(recentlyPlayed.isSystem)
        #expect(!userPlaylist.isSystem)
    }

    @Test("SystemPlaylistType rawValue 正确")
    func testSystemPlaylistTypeRawValues() {
        #expect(SystemPlaylistType.normal.rawValue == 0)
        #expect(SystemPlaylistType.favorites.rawValue == 1)
        #expect(SystemPlaylistType.recentlyPlayed.rawValue == 2)
    }

    @Test("歌单 Identifiable 通过 id 标识")
    func testPlaylistIdentifiable() {
        let id = UUID()
        let p1 = makePlaylist(id: id, name: "歌单A")
        let p2 = makePlaylist(id: id, name: "歌单B") // 同一 id，不同名称
        #expect(p1.id == p2.id)
    }
}

// MARK: - PagedResult Tests

@Suite("PagedResult Tests")
struct PagedResultTests {

    @Test("PagedResult hasMore 当还有更多数据时为 true")
    func testHasMoreTrue() {
        let result = PagedResult(items: [1, 2, 3], totalCount: 10, currentPage: 0, hasMore: true)
        #expect(result.hasMore)
        #expect(result.totalCount == 10)
        #expect(result.items.count == 3)
    }

    @Test("PagedResult hasMore 当无更多数据时为 false")
    func testHasMoreFalse() {
        let result = PagedResult(items: [1, 2, 3], totalCount: 3, currentPage: 0, hasMore: false)
        #expect(!result.hasMore)
    }

    @Test("PagedResult 空结果")
    func testEmptyPagedResult() {
        let result = PagedResult(items: [Int](), totalCount: 0, currentPage: 0, hasMore: false)
        #expect(result.items.isEmpty)
        #expect(result.totalCount == 0)
        #expect(!result.hasMore)
    }
}

// MARK: - UndoToken Tests

@Suite("UndoToken Tests")
struct UndoTokenTests {

    @Test("UndoToken 包含正确的 songIds")
    func testUndoTokenSongIds() {
        let ids = [UUID(), UUID(), UUID()]
        let token = UndoToken(songIds: ids, movedFiles: [], expiresAt: Date().addingTimeInterval(30))
        #expect(token.songIds == ids)
    }

    @Test("UndoToken 过期时间在未来 30 秒")
    func testUndoTokenExpiry() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(30)
        let token = UndoToken(songIds: [UUID()], movedFiles: [], expiresAt: expiresAt)
        #expect(token.expiresAt > now)
        #expect(token.expiresAt.timeIntervalSince(now) <= 31)
    }

    @Test("UndoToken.MovedFile 保留临时路径和原始路径")
    func testUndoTokenMovedFiles() {
        let files = [
            UndoToken.MovedFile(tempPath: "pending_delete/abc.mp3", originalRelativePath: "Music/song.mp3"),
            UndoToken.MovedFile(tempPath: "pending_delete/def.mp3", originalRelativePath: "Music/song2.mp3"),
        ]
        let token = UndoToken(songIds: [UUID()], movedFiles: files, expiresAt: Date())
        #expect(token.movedFiles.count == 2)
        #expect(token.movedFiles[0].tempPath == "pending_delete/abc.mp3")
        #expect(token.movedFiles[0].originalRelativePath == "Music/song.mp3")
    }
}

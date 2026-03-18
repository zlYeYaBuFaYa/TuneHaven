import Testing
import Foundation
@testable import TuneHaven

// MARK: - TimeInterval.formattedTime Tests

@Suite("TimeInterval.formattedTime Tests")
struct TimeIntervalFormattedTests {

    @Test("0 秒格式化为 0:00")
    func testZeroSeconds() {
        #expect((0 as TimeInterval).formattedTime == "0:00")
    }

    @Test("59 秒格式化为 0:59")
    func testUnderOneMinute() {
        #expect((59 as TimeInterval).formattedTime == "0:59")
    }

    @Test("60 秒格式化为 1:00")
    func testOneMinute() {
        #expect((60 as TimeInterval).formattedTime == "1:00")
    }

    @Test("90 秒格式化为 1:30")
    func testOneMinuteThirty() {
        #expect((90 as TimeInterval).formattedTime == "1:30")
    }

    @Test("65 秒（1 分 5 秒）格式化为 1:05（秒数补零）")
    func testSingleDigitSeconds() {
        #expect((65 as TimeInterval).formattedTime == "1:05")
    }

    @Test("227 秒格式化为 3:47（典型歌曲时长）")
    func testTypicalSongDuration() {
        #expect((227 as TimeInterval).formattedTime == "3:47")
    }

    @Test("3600 秒格式化为 1:00:00（整一小时）")
    func testOneHour() {
        #expect((3600 as TimeInterval).formattedTime == "1:00:00")
    }

    @Test("3661 秒格式化为 1:01:01（超过 1 小时带时、分、秒）")
    func testOverOneHour() {
        #expect((3661 as TimeInterval).formattedTime == "1:01:01")
    }

    @Test("3599 秒格式化为 59:59（不满 1 小时不显示小时位）")
    func testJustUnderOneHour() {
        #expect((3599 as TimeInterval).formattedTime == "59:59")
    }

    @Test("7322 秒格式化为 2:02:02")
    func testTwoHoursTwoMinutes() {
        #expect((7322 as TimeInterval).formattedTime == "2:02:02")
    }
}

// MARK: - QueueAddResult Tests

@Suite("QueueAddResult Tests")
struct QueueAddResultTests {

    @Test("success 与 success 相等（Equatable）")
    func testSuccessEquality() {
        #expect(QueueAddResult.success == .success)
    }

    @Test("queueFull 相同 count 时相等")
    func testQueueFullEquality() {
        #expect(QueueAddResult.queueFull(currentCount: 999) == .queueFull(currentCount: 999))
    }

    @Test("success 与 queueFull 不相等")
    func testSuccessNotEqualQueueFull() {
        #expect(QueueAddResult.success != .queueFull(currentCount: 0))
    }

    @Test("不同 count 的 queueFull 不相等")
    func testQueueFullDifferentCounts() {
        #expect(QueueAddResult.queueFull(currentCount: 100) != .queueFull(currentCount: 200))
    }
}

// MARK: - ImportFileStatus Tests

@Suite("ImportFileStatus Tests")
struct ImportFileStatusTests {

    @Test("ImportFileStatus 包含所有 6 种状态（不崩溃）")
    func testAllCasesExist() {
        let statuses: [ImportFileStatus] = [
            .success,
            .successIncompleteMetadata,
            .skippedDuplicate,
            .skippedUnsupportedFormat,
            .skippedOversize,
            .failed
        ]
        #expect(statuses.count == 6)
    }
}

// MARK: - ImportProgress Tests

@Suite("ImportProgress Tests")
struct ImportProgressTests {

    @Test("进度结构体包含正确字段")
    func testProgressFields() {
        let progress = ImportProgress(
            currentFileName: "song.mp3",
            completedCount: 3,
            totalCount: 10,
            percentage: 0.3,
            estimatedRemainingSeconds: 15.0
        )
        #expect(progress.currentFileName == "song.mp3")
        #expect(progress.completedCount == 3)
        #expect(progress.totalCount == 10)
        #expect(abs(progress.percentage - 0.3) < 0.001)
        #expect(progress.estimatedRemainingSeconds == 15.0)
    }

    @Test("进度百分比在 0 到 1 之间")
    func testProgressPercentageRange() {
        let half = ImportProgress(
            currentFileName: "file.mp3",
            completedCount: 5,
            totalCount: 10,
            percentage: 0.5,
            estimatedRemainingSeconds: nil
        )
        #expect(half.percentage >= 0.0)
        #expect(half.percentage <= 1.0)
    }

    @Test("estimatedRemainingSeconds 可以为 nil")
    func testProgressNoEstimate() {
        let progress = ImportProgress(
            currentFileName: "first.mp3",
            completedCount: 0,
            totalCount: 5,
            percentage: 0.0,
            estimatedRemainingSeconds: nil
        )
        #expect(progress.estimatedRemainingSeconds == nil)
    }
}

// MARK: - ImportResult Tests

@Suite("ImportResult Tests")
struct ImportResultTests {

    @Test("所有字段全为 0 时的初始状态")
    func testAllZeroFields() {
        let result = ImportResult(
            successCount: 0,
            skippedDuplicateCount: 0,
            skippedFormatCount: 0,
            failedCount: 0,
            incompleteMetadataCount: 0,
            skippedOversizeCount: 0,
            details: []
        )
        #expect(result.successCount == 0)
        #expect(result.skippedDuplicateCount == 0)
        #expect(result.skippedFormatCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.incompleteMetadataCount == 0)
        #expect(result.skippedOversizeCount == 0)
        #expect(result.details.isEmpty)
    }

    @Test("包含正确的导入详情列表")
    func testDetailsContainCorrectFiles() {
        let detail = SingleImportResult(fileName: "夜曲.mp3", status: .success, song: nil, errorMessage: nil)
        let result = ImportResult(
            successCount: 1,
            skippedDuplicateCount: 0,
            skippedFormatCount: 0,
            failedCount: 0,
            incompleteMetadataCount: 0,
            skippedOversizeCount: 0,
            details: [detail]
        )
        #expect(result.successCount == 1)
        #expect(result.details.count == 1)
        #expect(result.details[0].fileName == "夜曲.mp3")
        #expect(result.details[0].status == .success)
    }

    @Test("失败详情包含错误信息")
    func testFailedDetailHasErrorMessage() {
        let detail = SingleImportResult(
            fileName: "corrupt.mp3",
            status: .failed,
            song: nil,
            errorMessage: "文件损坏"
        )
        #expect(detail.errorMessage == "文件损坏")
        #expect(detail.song == nil)
    }

    @Test("跳过重复详情的状态正确")
    func testSkippedDuplicateDetail() {
        let detail = SingleImportResult(fileName: "dup.mp3", status: .skippedDuplicate, song: nil, errorMessage: nil)
        #expect(detail.status == .skippedDuplicate)
        #expect(detail.errorMessage == nil)
    }

    @Test("总数量可以从各统计字段相加")
    func testTotalCount() {
        let result = ImportResult(
            successCount: 5,
            skippedDuplicateCount: 2,
            skippedFormatCount: 1,
            failedCount: 1,
            incompleteMetadataCount: 2,
            skippedOversizeCount: 1,
            details: []
        )
        let total = result.successCount + result.skippedDuplicateCount
            + result.skippedFormatCount + result.failedCount + result.skippedOversizeCount
        #expect(total == 10)
    }
}

// MARK: - WiFiConnectionState Tests

@Suite("WiFiConnectionState Tests")
struct WiFiConnectionStateTests {

    @Test("idle 与 idle 相等")
    func testIdleEquality() {
        #expect(WiFiConnectionState.idle == .idle)
    }

    @Test("connected 相同 IP 时相等")
    func testConnectedSameIP() {
        #expect(WiFiConnectionState.connected(ip: "192.168.1.1") == .connected(ip: "192.168.1.1"))
    }

    @Test("connected 不同 IP 时不相等")
    func testConnectedDifferentIPs() {
        #expect(WiFiConnectionState.connected(ip: "192.168.1.1") != .connected(ip: "192.168.1.2"))
    }

    @Test("transferring 相同 IP 时相等")
    func testTransferringSameIP() {
        #expect(WiFiConnectionState.transferring(ip: "10.0.0.1") == .transferring(ip: "10.0.0.1"))
    }

    @Test("transferring 不同 IP 时不相等")
    func testTransferringDifferentIPs() {
        #expect(WiFiConnectionState.transferring(ip: "10.0.0.1") != .transferring(ip: "10.0.0.2"))
    }

    @Test("idle 与 connected 不相等")
    func testIdleNotConnected() {
        #expect(WiFiConnectionState.idle != .connected(ip: "192.168.1.1"))
    }

    @Test("connected 与 transferring 不相等（即使 IP 相同）")
    func testConnectedNotTransferring() {
        #expect(WiFiConnectionState.connected(ip: "192.168.1.1") != .transferring(ip: "192.168.1.1"))
    }
}

// MARK: - WiFiTransferProgress Tests

@Suite("WiFiTransferProgress Tests")
struct WiFiTransferProgressTests {

    @Test("结构体包含正确字段值")
    func testProgressFields() {
        let progress = WiFiTransferProgress(
            fileName: "song.mp3",
            bytesReceived: 5 * 1024 * 1024,
            totalBytes: 10 * 1024 * 1024,
            speed: 1024.0
        )
        #expect(progress.fileName == "song.mp3")
        #expect(progress.bytesReceived == 5 * 1024 * 1024)
        #expect(progress.totalBytes == 10 * 1024 * 1024)
        #expect(progress.speed == 1024.0)
    }

    @Test("bytesReceived 不超过 totalBytes")
    func testBytesNotExceedsTotal() {
        let progress = WiFiTransferProgress(
            fileName: "file.mp3",
            bytesReceived: 3 * 1024 * 1024,
            totalBytes: 10 * 1024 * 1024,
            speed: 500.0
        )
        #expect(progress.bytesReceived <= progress.totalBytes)
    }

    @Test("传输完成时 bytesReceived 等于 totalBytes")
    func testCompletedTransfer() {
        let size: Int64 = 8 * 1024 * 1024
        let progress = WiFiTransferProgress(
            fileName: "done.mp3",
            bytesReceived: size,
            totalBytes: size,
            speed: 2048.0
        )
        #expect(progress.bytesReceived == progress.totalBytes)
    }
}

// MARK: - RecentPlayRange Tests

@Suite("RecentPlayRange Tests")
struct RecentPlayRangeTests {

    @Test("包含 5 种选项")
    func testCasesCount() {
        #expect(RecentPlayRange.allCases.count == 5)
    }

    @Test("rawValue（即 days）与枚举语义一致")
    func testRawValues() {
        #expect(RecentPlayRange.three.days == 3)
        #expect(RecentPlayRange.seven.days == 7)
        #expect(RecentPlayRange.fourteen.days == 14)
        #expect(RecentPlayRange.thirty.days == 30)
        #expect(RecentPlayRange.all.days == 0)
    }

    @Test("所有选项的 displayName 不为空")
    func testDisplayNamesNotEmpty() {
        for range in RecentPlayRange.allCases {
            #expect(!range.displayName.isEmpty, "\(range) 的 displayName 不应为空")
        }
    }

    @Test("displayName 包含数字或「全部」")
    func testDisplayNamesContainNumbers() {
        #expect(RecentPlayRange.three.displayName.contains("3"))
        #expect(RecentPlayRange.seven.displayName.contains("7"))
        #expect(RecentPlayRange.fourteen.displayName.contains("14"))
        #expect(RecentPlayRange.thirty.displayName.contains("30"))
        #expect(RecentPlayRange.all.displayName.contains("全部") || !RecentPlayRange.all.displayName.isEmpty)
    }

    @Test("init?(days:) 可从有效天数初始化")
    func testInitFromDays() {
        #expect(RecentPlayRange(days: 3) == .three)
        #expect(RecentPlayRange(days: 7) == .seven)
        #expect(RecentPlayRange(days: 14) == .fourteen)
        #expect(RecentPlayRange(days: 30) == .thirty)
        #expect(RecentPlayRange(days: 0) == .all)
    }

    @Test("init?(days:) 无效天数返回 nil")
    func testInitFromInvalidDays() {
        #expect(RecentPlayRange(days: 99) == nil)
        #expect(RecentPlayRange(days: -1) == nil)
        #expect(RecentPlayRange(days: 1) == nil)
    }

    @Test("Identifiable id 等于 rawValue")
    func testIdentifiableId() {
        #expect(RecentPlayRange.seven.id == 7)
        #expect(RecentPlayRange.all.id == 0)
        #expect(RecentPlayRange.thirty.id == 30)
    }
}

// MARK: - LibraryTab Tests (扩展)

@Suite("LibraryTab Extended Tests")
struct LibraryTabExtendedTests {

    @Test("rawValue 与枚举名称对应")
    func testRawValues() {
        #expect(LibraryTab.all.rawValue == "all")
        #expect(LibraryTab.artist.rawValue == "artist")
        #expect(LibraryTab.album.rawValue == "album")
    }

    @Test("可从合法 rawValue 初始化")
    func testInitFromRawValue() {
        #expect(LibraryTab(rawValue: "all") == .all)
        #expect(LibraryTab(rawValue: "artist") == .artist)
        #expect(LibraryTab(rawValue: "album") == .album)
    }

    @Test("非法 rawValue 初始化返回 nil")
    func testInvalidRawValueReturnsNil() {
        #expect(LibraryTab(rawValue: "songs") == nil)
        #expect(LibraryTab(rawValue: "") == nil)
    }

    @Test("allCases 包含 3 个选项")
    func testAllCasesCount() {
        #expect(LibraryTab.allCases.count == 3)
    }

    @Test("displayName 与语义一致")
    func testDisplayNameContent() {
        #expect(LibraryTab.all.displayName == "全部")
        #expect(LibraryTab.artist.displayName == "艺术家")
        #expect(LibraryTab.album.displayName == "专辑")
    }
}

// MARK: - PlaylistGroup Tests

@Suite("PlaylistGroup Tests")
struct PlaylistGroupTests {

    @Test("id 默认唯一")
    func testUniqueIds() {
        let g1 = PlaylistGroup(id: UUID(), name: "分组A", createdAt: Date(), sortOrder: 0)
        let g2 = PlaylistGroup(id: UUID(), name: "分组B", createdAt: Date(), sortOrder: 1)
        #expect(g1.id != g2.id)
    }

    @Test("相同 id 的两个分组相等（Hashable 基于 id）")
    func testEqualityById() {
        let id = UUID()
        let g1 = PlaylistGroup(id: id, name: "A", createdAt: Date(), sortOrder: 0)
        let g2 = PlaylistGroup(id: id, name: "B", createdAt: Date(), sortOrder: 5)
        #expect(g1 == g2)
    }

    @Test("name 字段可变更")
    func testNameIsMutable() {
        var group = PlaylistGroup(id: UUID(), name: "原名", createdAt: Date(), sortOrder: 0)
        group.name = "新名称"
        #expect(group.name == "新名称")
    }

    @Test("sortOrder 字段可变更")
    func testSortOrderIsMutable() {
        var group = PlaylistGroup(id: UUID(), name: "分组", createdAt: Date(), sortOrder: 0)
        group.sortOrder = 10
        #expect(group.sortOrder == 10)
    }

    @Test("可加入 Set（Hashable 验证）")
    func testHashableInSet() {
        let id1 = UUID()
        let id2 = UUID()
        let g1 = PlaylistGroup(id: id1, name: "G1", createdAt: Date(), sortOrder: 0)
        let g2 = PlaylistGroup(id: id1, name: "G1-copy", createdAt: Date(), sortOrder: 1)
        let g3 = PlaylistGroup(id: id2, name: "G2", createdAt: Date(), sortOrder: 2)

        let set: Set<PlaylistGroup> = [g1, g2, g3]
        #expect(set.count == 2) // g1 和 g2 的 id 相同，只算一个
    }
}

// MARK: - PlaylistGroupDetail Tests

@Suite("PlaylistGroupDetail Tests")
struct PlaylistGroupDetailTests {

    private func makePlaylist(name: String, songCount: Int, groupId: UUID) -> Playlist {
        Playlist(
            id: UUID(), name: name, description: nil, coverImagePath: nil,
            autoCoverHash: nil, isSystem: false, systemType: .normal, songCount: songCount,
            groupId: groupId, sortOrder: 0, createdAt: Date(), updatedAt: Date()
        )
    }

    @Test("包含正确的 name 和 playlists")
    func testBasicProperties() {
        let id = UUID()
        let p = makePlaylist(name: "摇滚", songCount: 5, groupId: id)
        let detail = PlaylistGroupDetail(id: id, name: "我的分组", playlists: [p], totalSongCount: 5)

        #expect(detail.name == "我的分组")
        #expect(detail.playlists.count == 1)
        #expect(detail.totalSongCount == 5)
    }

    @Test("totalSongCount 等于所有歌单歌曲总数")
    func testTotalSongCount() {
        let id = UUID()
        let p1 = makePlaylist(name: "P1", songCount: 10, groupId: id)
        let p2 = makePlaylist(name: "P2", songCount: 20, groupId: id)

        let detail = PlaylistGroupDetail(
            id: id, name: "合计",
            playlists: [p1, p2],
            totalSongCount: p1.songCount + p2.songCount
        )
        #expect(detail.totalSongCount == 30)
    }

    @Test("空分组（无歌单）的 totalSongCount 为 0")
    func testEmptyGroupDetail() {
        let detail = PlaylistGroupDetail(id: UUID(), name: "空分组", playlists: [], totalSongCount: 0)
        #expect(detail.playlists.isEmpty)
        #expect(detail.totalSongCount == 0)
    }
}

// MARK: - LyricsData Tests

@Suite("LyricsData Tests")
struct LyricsDataTests {

    @Test("包含正确的 source、lines 和 rawText")
    func testProperties() {
        let line = LyricsLine(timestamp: 10.0, text: "测试歌词")
        let data = LyricsData(source: .file, lines: [line], rawText: "[00:10.00]测试歌词")

        #expect(data.source == .file)
        #expect(data.lines.count == 1)
        #expect(data.rawText == "[00:10.00]测试歌词")
    }

    @Test("嵌入式歌词 source 为 embedded")
    func testEmbeddedSource() {
        let data = LyricsData(source: .embedded, lines: [], rawText: "")
        #expect(data.source == .embedded)
    }

    @Test("手动输入歌词 source 为 manual")
    func testManualSource() {
        let data = LyricsData(source: .manual, lines: [], rawText: "手动输入")
        #expect(data.source == .manual)
    }

    @Test("空歌词 lines 为空数组")
    func testEmptyLines() {
        let data = LyricsData(source: .embedded, lines: [], rawText: "")
        #expect(data.lines.isEmpty)
    }

    @Test("LyricsLine 的 timestamp 和 text 属性正确")
    func testLyricsLineProperties() {
        let line = LyricsLine(timestamp: 125.5, text: "夜曲")
        #expect(abs(line.timestamp - 125.5) < 0.001)
        #expect(line.text == "夜曲")
    }

    @Test("LyricsLine 初始化时自动生成唯一 id")
    func testLyricsLineUniqueId() {
        let a = LyricsLine(timestamp: 10.0, text: "行一")
        let b = LyricsLine(timestamp: 10.0, text: "行一") // 相同参数
        #expect(a.id != b.id)
    }
}

// MARK: - SearchResult Tests

@Suite("SearchResult Tests")
struct SearchResultTests {

    @Test("SearchResult.empty 所有集合为空")
    func testEmptySearchResult() {
        let empty = SearchResult.empty
        #expect(empty.songs.isEmpty)
        #expect(empty.artists.isEmpty)
        #expect(empty.albums.isEmpty)
    }

    @Test("SearchResult.empty 所有统计为 0")
    func testEmptyStatsCounts() {
        let empty = SearchResult.empty
        #expect(empty.totalSongCount == 0)
        #expect(empty.totalArtistCount == 0)
        #expect(empty.totalAlbumCount == 0)
    }

    @Test("SearchResult 统计数与实际列表长度一致")
    func testCountsMatchListSizes() {
        let result = SearchResult(
            songs: [makeMinimalSong(), makeMinimalSong()],
            artists: [ArtistGroup(name: "A", songCount: 2, albumCount: 1)],
            albums: [],
            totalSongCount: 2,
            totalArtistCount: 1,
            totalAlbumCount: 0
        )
        #expect(result.songs.count == result.totalSongCount)
        #expect(result.artists.count == result.totalArtistCount)
        #expect(result.albums.count == result.totalAlbumCount)
    }
}

// MARK: - SearchHistoryItem Tests

@Suite("SearchHistoryItem Tests")
struct SearchHistoryItemTests {

    @Test("两个不同 SearchHistoryItem 的 id 唯一")
    func testUniqueIds() {
        let item1 = SearchHistoryItem(id: UUID(), keyword: "周杰伦", searchedAt: Date())
        let item2 = SearchHistoryItem(id: UUID(), keyword: "周杰伦", searchedAt: Date())
        #expect(item1.id != item2.id)
    }

    @Test("keyword 字段正确存储")
    func testKeywordStored() {
        let item = SearchHistoryItem(id: UUID(), keyword: "夜曲", searchedAt: Date())
        #expect(item.keyword == "夜曲")
    }

    @Test("searchedAt 字段正确存储")
    func testSearchedAtStored() {
        let now = Date()
        let item = SearchHistoryItem(id: UUID(), keyword: "test", searchedAt: now)
        #expect(item.searchedAt == now)
    }

    @Test("Identifiable id 即为 UUID")
    func testIdentifiable() {
        let id = UUID()
        let item = SearchHistoryItem(id: id, keyword: "query", searchedAt: Date())
        #expect(item.id == id)
    }
}

// MARK: - ArtistDetail / AlbumDetail Tests

@Suite("ArtistDetail Tests")
struct ArtistDetailTests {

    @Test("ArtistDetail 包含正确的 name 和 songs")
    func testProperties() {
        let song = makeMinimalSong(title: "夜曲", artist: "周杰伦", album: "十一月的萧邦")
        let album = AlbumGroup(name: "十一月的萧邦", artist: "周杰伦", year: 2003, songCount: 1, coverImagePath: nil)
        let detail = ArtistDetail(name: "周杰伦", albums: [album], allSongs: [song])

        #expect(detail.name == "周杰伦")
        #expect(detail.allSongs.count == 1)
        #expect(detail.albums.count == 1)
    }
}

@Suite("AlbumDetail Tests")
struct AlbumDetailTests {

    @Test("AlbumDetail 包含正确的 name、artist、songs")
    func testProperties() {
        let s1 = makeMinimalSong(title: "夜曲", artist: "周杰伦", album: "十一月的萧邦")
        let s2 = makeMinimalSong(title: "枫", artist: "周杰伦", album: "十一月的萧邦")
        let detail = AlbumDetail(
            name: "十一月的萧邦",
            artist: "周杰伦",
            year: 2003,
            songs: [s1, s2],
            coverImagePath: nil
        )

        #expect(detail.name == "十一月的萧邦")
        #expect(detail.artist == "周杰伦")
        #expect(detail.year == 2003)
        #expect(detail.songs.count == 2)
        #expect(detail.coverImagePath == nil)
    }

    @Test("AlbumDetail year 可以为 nil")
    func testYearOptional() {
        let detail = AlbumDetail(name: "未知专辑", artist: "未知艺术家", year: nil, songs: [], coverImagePath: nil)
        #expect(detail.year == nil)
    }
}

// MARK: - PagedResult Extended Tests

@Suite("PagedResult Extended Tests")
struct PagedResultExtendedTests {

    @Test("currentPage 字段正确存储")
    func testCurrentPage() {
        let result = PagedResult(items: [1, 2, 3], totalCount: 100, currentPage: 5, hasMore: true)
        #expect(result.currentPage == 5)
    }

    @Test("items 泛型支持 Song 类型")
    func testGenericSongType() {
        let song = makeMinimalSong()
        let result = PagedResult(items: [song], totalCount: 1, currentPage: 0, hasMore: false)
        #expect(result.items.count == 1)
    }

    @Test("多页时 hasMore 为 true，最后一页为 false")
    func testHasMorePagination() {
        let page1 = PagedResult(items: Array(1...10), totalCount: 25, currentPage: 0, hasMore: true)
        let page3 = PagedResult(items: Array(21...25), totalCount: 25, currentPage: 2, hasMore: false)
        #expect(page1.hasMore)
        #expect(!page3.hasMore)
    }
}

// MARK: - Shared Helpers

private func makeMinimalSong(
    id: UUID = UUID(),
    title: String = "T",
    artist: String = "A",
    album: String = "B"
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
            format: "mp3",
            sampleRate: 44100,
            bitRate: 320,
            channels: 2,
            encoder: nil,
            trackNumber: nil,
            year: nil,
            genre: nil
        ),
        importDate: Date(),
        fileSize: 1024 * 1024,
        playCount: 0,
        isFavorite: false,
        favoriteDate: nil,
        lastPlayedDate: nil
    )
}

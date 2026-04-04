import Testing
import Foundation
@testable import TuneHaven

// MARK: - SearchService Tests

@Suite("SearchService Tests")
struct SearchServiceTests {

    private var testSongs: [Song] {
        [
            makeSong(title: "夜曲", artist: "周杰伦", album: "十一月的萧邦"),
            makeSong(title: "晴天", artist: "周杰伦", album: "叶惠美"),
            makeSong(title: "七里香", artist: "周杰伦", album: "七里香"),
            makeSong(title: "稻香", artist: "周杰伦", album: "魔杰座"),
            makeSong(title: "青花瓷", artist: "周杰伦", album: "我很忙"),
            makeSong(title: "告白气球", artist: "周杰伦", album: "周杰伦的床边故事"),
            makeSong(title: "Perfect", artist: "Ed Sheeran", album: "÷ (Divide)"),
            makeSong(title: "Shape of You", artist: "Ed Sheeran", album: "÷ (Divide)"),
            makeSong(title: "Rolling in the Deep", artist: "Adele", album: "21"),
            makeSong(title: "Hello", artist: "Adele", album: "25"),
        ]
    }

    // MARK: - 空查询测试

    @Test("空查询返回空结果", .serialized)
    @MainActor func testSearchEmptyQuery() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "", tab: .all, allSongs: testSongs)

        #expect(result.songs.isEmpty)
        #expect(result.artists.isEmpty)
        #expect(result.albums.isEmpty)
        #expect(result.totalMatchCount == 0)
    }

    @Test("纯空白字符查询返回空结果", .serialized)
    @MainActor func testSearchWhitespaceQuery() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "   ", tab: .all, allSongs: testSongs)

        #expect(result.songs.isEmpty)
        #expect(result.totalMatchCount == 0)
    }

    // MARK: - 歌曲名称搜索

    @Test("按歌曲名称前缀搜索", .serialized)
    @MainActor func testSearchByTitlePrefix() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "夜", tab: .all, allSongs: testSongs)

        #expect(result.totalMatchCount == 1)
        #expect(result.songs.first?.title == "夜曲")
    }

    @Test("按歌曲名称搜索匹配多首歌曲", .serialized)
    @MainActor func testSearchByTitleMultipleMatches() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        // "P" 匹配 "Perfect"
        let result = await service.search(query: "P", tab: .all, allSongs: testSongs)

        #expect(result.totalMatchCount >= 1)
        #expect(result.songs.contains { $0.title == "Perfect" })
    }

    @Test("歌曲名称搜索中间部分不匹配（前缀匹配）", .serialized)
    @MainActor func testSearchTitleMiddleNotMatched() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "曲", tab: .all, allSongs: testSongs)

        #expect(result.songs.contains { $0.title == "夜曲" })
    }

    // MARK: - 艺术家搜索

    @Test("按艺术家名称前缀搜索", .serialized)
    @MainActor func testSearchByArtistPrefix() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "周杰伦", tab: .all, allSongs: testSongs)

        #expect(result.totalMatchCount == 6)
        #expect(result.songs.allSatisfy { $0.artist == "周杰伦" })
    }

    @Test("搜索艺术家时分组统计正确", .serialized)
    @MainActor func testSearchArtistGrouping() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "周", tab: .all, allSongs: testSongs)

        #expect(result.totalArtistCount == 1)
        #expect(result.artists.first?.name == "周杰伦")
        #expect(result.artists.first?.songCount == 6)
    }

    @Test("搜索返回多个艺术家分组", .serialized)
    @MainActor func testSearchMultipleArtists() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        // "A" 匹配 "Adele"
        let result = await service.search(query: "A", tab: .all, allSongs: testSongs)

        #expect(result.totalArtistCount >= 1)
        #expect(result.artists.contains { $0.name == "Adele" })
    }

    // MARK: - 专辑搜索

    @Test("按专辑名称前缀搜索", .serialized)
    @MainActor func testSearchByAlbumPrefix() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "七里香", tab: .all, allSongs: testSongs)

        #expect(result.totalAlbumCount == 1)
        #expect(result.albums.first?.name == "七里香")
    }

    @Test("搜索专辑时统计歌曲数量正确", .serialized)
    @MainActor func testSearchAlbumSongCount() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        // "÷" 匹配 Ed Sheeran 的专辑 "÷ (Divide)"，包含2首歌
        let result = await service.search(query: "÷", tab: .all, allSongs: testSongs)

        let divideAlbum = result.albums.first { $0.name.hasPrefix("÷") }
        #expect(divideAlbum?.songCount == 2)
    }

    // MARK: - 大小写不敏感

    @Test("搜索大小写不敏感", .serialized)
    @MainActor func testSearchCaseInsensitive() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let resultLower = await service.search(query: "perfect", tab: .all, allSongs: testSongs)
        let resultUpper = await service.search(query: "PERFECT", tab: .all, allSongs: testSongs)
        let resultMixed = await service.search(query: "Perfect", tab: .all, allSongs: testSongs)

        #expect(resultLower.totalMatchCount == resultUpper.totalMatchCount)
        #expect(resultLower.totalMatchCount == resultMixed.totalMatchCount)
        #expect(resultLower.songs.contains { $0.title == "Perfect" })
    }

    @Test("搜索中文歌曲不受大小写影响", .serialized)
    @MainActor func testSearchChineseCaseInsensitive() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "晴天", tab: .all, allSongs: testSongs)
        #expect(result.totalMatchCount == 1)
        #expect(result.songs.first?.title == "晴天")
    }

    // MARK: - 无结果

    @Test("无匹配结果时返回空", .serialized)
    @MainActor func testSearchNoMatch() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "不存在的歌曲XYZ", tab: .all, allSongs: testSongs)

        #expect(result.songs.isEmpty)
        #expect(result.artists.isEmpty)
        #expect(result.albums.isEmpty)
        #expect(result.totalMatchCount == 0)
        #expect(result.totalArtistCount == 0)
        #expect(result.totalAlbumCount == 0)
    }

    // MARK: - SearchResult 结构

    @Test("搜索结果包含正确的统计信息", .serialized)
    @MainActor func testSearchResultCounts() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "Ed", tab: .all, allSongs: testSongs)

        // Ed Sheeran: 2首歌曲，1个艺术家，1个专辑
        #expect(result.totalMatchCount == 2)
        #expect(result.totalArtistCount == 1)
        #expect(result.totalAlbumCount == 1)
        #expect(result.songs.count == result.totalMatchCount)
        #expect(result.artists.count == result.totalArtistCount)
        #expect(result.albums.count == result.totalAlbumCount)
    }

    @Test("艺术家分组按名称排序", .serialized)
    @MainActor func testSearchArtistsSorted() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        // 搜索所有歌曲（使用通用前缀）
        let mixedSongs = [
            makeSong(title: "S1", artist: "Zebra Band"),
            makeSong(title: "S2", artist: "Apple Music"),
            makeSong(title: "S3", artist: "Middle Artist")
        ]
        let result = await service.search(query: "S", tab: .all, allSongs: mixedSongs)

        let artistNames = result.artists.map { $0.name }
        #expect(artistNames == artistNames.sorted())
    }

    @Test("专辑分组按名称排序", .serialized)
    @MainActor func testSearchAlbumsSorted() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let mixedSongs = [
            makeSong(title: "S1", artist: "A", album: "Z Album"),
            makeSong(title: "S2", artist: "A", album: "A Album"),
            makeSong(title: "S3", artist: "A", album: "M Album")
        ]
        let result = await service.search(query: "S", tab: .all, allSongs: mixedSongs)

        let albumNames = result.albums.map { $0.name }
        #expect(albumNames == albumNames.sorted())
    }

    // MARK: - 前导空白处理

    @Test("查询前后空白被裁剪", .serialized)
    @MainActor func testSearchTrimsWhitespace() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let resultWithSpaces = await service.search(query: "  晴天  ", tab: .all, allSongs: testSongs)
        let resultClean = await service.search(query: "晴天", tab: .all, allSongs: testSongs)

        #expect(resultWithSpaces.totalMatchCount == resultClean.totalMatchCount)
    }

    // MARK: - 空歌库搜索

    @Test("空歌库搜索返回空结果", .serialized)
    @MainActor func testSearchEmptyLibrary() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "周杰伦", tab: .all, allSongs: [])

        #expect(result.songs.isEmpty)
        #expect(result.totalMatchCount == 0)
    }

    // MARK: - 不同 Tab 搜索

    @Test("使用 artist tab 搜索返回结果", .serialized)
    @MainActor func testSearchWithArtistTab() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "周杰伦", tab: .artist, allSongs: testSongs)

        #expect(result.totalMatchCount == 6)
        #expect(result.totalArtistCount >= 1)
    }

    @Test("使用 album tab 搜索返回结果", .serialized)
    @MainActor func testSearchWithAlbumTab() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let result = await service.search(query: "七里香", tab: .album, allSongs: testSongs)

        #expect(result.totalAlbumCount >= 1)
    }

    @Test("不同 tab 下相同查询返回一致结果", .serialized)
    @MainActor func testSearchConsistentAcrossTabs() async {
        let service = SearchService(historyRepo: MockSearchHistoryRepository())
        let resultAll = await service.search(query: "Ed", tab: .all, allSongs: testSongs)
        let resultArtist = await service.search(query: "Ed", tab: .artist, allSongs: testSongs)
        let resultAlbum = await service.search(query: "Ed", tab: .album, allSongs: testSongs)

        #expect(resultAll.totalMatchCount == resultArtist.totalMatchCount)
        #expect(resultAll.totalMatchCount == resultAlbum.totalMatchCount)
    }
}

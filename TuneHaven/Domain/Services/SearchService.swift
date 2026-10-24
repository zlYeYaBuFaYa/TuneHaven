import Foundation

@MainActor
final class SearchService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var result = SearchResult.empty
    @Published private(set) var history: [SearchHistoryItem] = []

    private let historyRepo: SearchHistoryRepository
    private var currentSearchTask: Task<SearchResult, Never>?

    init(historyRepo: SearchHistoryRepository) {
        self.historyRepo = historyRepo
    }

    func search(query: String, tab: LibraryTab, allSongs: [Song]) async -> SearchResult {
        guard let prepared = PinyinSearchMatcher.prepare(query) else {
            return .empty
        }

        currentSearchTask?.cancel()

        log.debug("搜索: query=\(prepared.raw), tab=\(tab)")

        let task = Task.detached(priority: .userInitiated) { () -> SearchResult in
            guard !Task.isCancelled else { return .empty }
            let matched = allSongs.filter {
                PinyinSearchMatcher.matchesSong($0, query: prepared)
            }

            // 设计意图：按 Tab 缩小歌曲列表——artist 只保留艺术家字段命中，
            // album 只保留专辑字段命中。分组仍来自任一字段命中的歌曲。
            // 字段比较与「全部」使用同一套拼音规则，避免只能在全部里用拼音。
            let filteredSongs: [Song]
            switch tab {
            case .artist:
                filteredSongs = matched.filter {
                    PinyinSearchMatcher.matches(text: $0.artist, query: prepared)
                }
            case .album:
                filteredSongs = matched.filter {
                    PinyinSearchMatcher.matches(text: $0.album, query: prepared)
                }
            case .all:
                filteredSongs = matched
            }

            let artists = LibraryGrouping.artistGroups(from: matched)
            let albums = LibraryGrouping.albumGroups(from: matched)

            return SearchResult(songs: filteredSongs, artists: artists, albums: albums, totalMatchCount: matched.count, totalArtistCount: artists.count, totalAlbumCount: albums.count)
        }
        currentSearchTask = task
        let searchResult = await task.value

        guard !Task.isCancelled else { return .empty }
        self.result = searchResult
        return searchResult
    }

    func fetchHistory(tab: LibraryTab) async {
        history = await historyRepo.fetchHistory(tab: tab, limit: 10)
    }

    func saveHistory(keyword: String, tab: LibraryTab) async {
        try? await historyRepo.saveHistory(keyword: keyword, tab: tab)
    }

    func deleteHistory(id: UUID) async {
        try? await historyRepo.deleteHistory(id: id)
    }

    func clearHistory() async {
        log.info("清除搜索历史")
        try? await historyRepo.clearHistory()
    }

    func clearHistory(tab: LibraryTab) async {
        log.info("清除搜索历史: tab=\(tab.rawValue)")
        try? await historyRepo.clearHistory(tab: tab)
    }
}

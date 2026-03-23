import Foundation

@MainActor
final class SearchService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var result = SearchResult.empty
    @Published private(set) var history: [SearchHistoryItem] = []

    private let historyRepo: SearchHistoryRepository

    init(historyRepo: SearchHistoryRepository) {
        self.historyRepo = historyRepo
    }

    func search(query: String, tab: LibraryTab, allSongs: [Song]) async -> SearchResult {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return .empty
        }

        log.debug("搜索: query=\(q), tab=\(tab)")

        let searchResult: SearchResult = await Task.detached(priority: .userInitiated) {
            let matched = allSongs.filter {
                $0.title.lowercased().contains(q) ||
                $0.artist.lowercased().contains(q) ||
                $0.album.lowercased().contains(q)
            }

            let filteredSongs: [Song]
            switch tab {
            case .artist:
                filteredSongs = matched.filter { $0.artist.lowercased().contains(q) }
            case .album:
                filteredSongs = matched.filter { $0.album.lowercased().contains(q) }
            case .all:
                filteredSongs = matched
            }

            let artists = ArtistGroup.group(from: matched)
            let albums = AlbumGroup.group(from: matched)

            return SearchResult(songs: filteredSongs, artists: artists, albums: albums, totalMatchCount: matched.count, totalArtistCount: artists.count, totalAlbumCount: albums.count)
        }.value

        self.result = searchResult
        return searchResult
    }

    func fetchHistory(tab: LibraryTab) async {
        history = await historyRepo.fetchHistory(tab: tab, limit: 10)
    }

    func saveHistory(keyword: String, tab: LibraryTab) async {
        await historyRepo.saveHistory(keyword: keyword, tab: tab)
    }

    func deleteHistory(id: UUID) async {
        await historyRepo.deleteHistory(id: id)
    }

    func clearHistory() async {
        log.info("清除搜索历史")
        await historyRepo.clearHistory()
    }

    func clearHistory(tab: LibraryTab) async {
        log.info("清除搜索历史: tab=\(tab.rawValue)")
        await historyRepo.clearHistory(tab: tab)
    }
}

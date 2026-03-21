import Foundation

@MainActor
final class SearchService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var result = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
    @Published private(set) var history: [SearchHistoryItem] = []

    private let historyRepo: SearchHistoryRepository

    init(historyRepo: SearchHistoryRepository = CoreDataSearchHistoryRepository()) {
        self.historyRepo = historyRepo
    }

    func search(query: String, tab: LibraryTab, allSongs: [Song]) async -> SearchResult {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
        }

        log.debug("搜索: query=\(q), tab=\(tab)")
        let matched = allSongs.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.album.lowercased().contains(q)
        }

        var artistCounts: [String: (songs: Int, albums: Set<String>)] = [:]
        for song in matched {
            var g = artistCounts[song.artist] ?? (0, [])
            g.songs += 1; g.albums.insert(song.album)
            artistCounts[song.artist] = g
        }
        let artists = artistCounts.map { ArtistGroup(name: $0.key, songCount: $0.value.songs, albumCount: $0.value.albums.count) }.sorted { $0.name < $1.name }

        struct AlbumKey: Hashable { let artist: String; let album: String }
        var albumData: [AlbumKey: (year: Int?, count: Int, cover: String?)] = [:]
        for song in matched {
            let key = AlbumKey(artist: song.artist, album: song.album)
            var g = albumData[key] ?? (song.metadata.year, 0, song.coverImagePath)
            g.count += 1; albumData[key] = g
        }
        let albums = albumData.map { AlbumGroup(name: $0.key.album, artist: $0.key.artist, year: $0.value.year, songCount: $0.value.count, coverImagePath: $0.value.cover) }.sorted { $0.name < $1.name }

        let searchResult = SearchResult(songs: matched, artists: artists, albums: albums, totalSongCount: matched.count, totalArtistCount: artists.count, totalAlbumCount: albums.count)
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

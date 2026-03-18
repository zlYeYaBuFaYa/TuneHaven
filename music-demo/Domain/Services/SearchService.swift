import CoreData
import Foundation

@MainActor
final class SearchService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var result = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
    @Published private(set) var history: [SearchHistoryItem] = []

    private let stack = CoreDataStack.shared

    func search(query: String, tab: LibraryTab, allSongs: [Song]) async -> SearchResult {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
        }

        log.debug("搜索: query=\(q), tab=\(tab)")
        let matched = allSongs.filter {
            $0.title.lowercased().hasPrefix(q) ||
            $0.artist.lowercased().hasPrefix(q) ||
            $0.album.lowercased().hasPrefix(q)
        }

        var artistNames = Set<String>()
        var albumKeys = Set<String>()
        var artists: [ArtistGroup] = []
        var albums: [AlbumGroup] = []

        for song in matched {
            if !artistNames.contains(song.artist) {
                artistNames.insert(song.artist)
            }
            let key = "\(song.artist)/\(song.album)"
            if !albumKeys.contains(key) {
                albumKeys.insert(key)
            }
        }

        var artistCounts: [String: (songs: Int, albums: Set<String>)] = [:]
        for song in matched {
            var g = artistCounts[song.artist] ?? (0, [])
            g.songs += 1; g.albums.insert(song.album)
            artistCounts[song.artist] = g
        }
        artists = artistCounts.map { ArtistGroup(name: $0.key, songCount: $0.value.songs, albumCount: $0.value.albums.count) }.sorted { $0.name < $1.name }

        var albumData: [String: (artist: String, year: Int?, count: Int, cover: String?)] = [:]
        for song in matched {
            let key = "\(song.artist)/\(song.album)"
            var g = albumData[key] ?? (song.artist, song.metadata.year, 0, song.coverImagePath)
            g.count += 1; albumData[key] = g
        }
        albums = albumData.map { AlbumGroup(name: String($0.key.split(separator: "/").last ?? ""), artist: $0.value.artist, year: $0.value.year, songCount: $0.value.count, coverImagePath: $0.value.cover) }.sorted { $0.name < $1.name }

        return SearchResult(songs: matched, artists: artists, albums: albums, totalSongCount: matched.count, totalArtistCount: artists.count, totalAlbumCount: albums.count)
    }

    func fetchHistory(tab: LibraryTab) async {
        history = await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SearchHistoryEntity.fetchRequest()
                request.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                request.sortDescriptors = [NSSortDescriptor(key: "searchedAt", ascending: false)]
                request.fetchLimit = 10
                let results = (try? self.stack.viewContext.fetch(request)) ?? []
                continuation.resume(returning: results.compactMap { entity -> SearchHistoryItem? in
                    guard let id = entity.id, let keyword = entity.keyword, let date = entity.searchedAt else { return nil }
                    return SearchHistoryItem(id: id, keyword: keyword, searchedAt: date)
                })
            }
        }
    }

    func saveHistory(keyword: String, tab: LibraryTab) async {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        try? await stack.performBackground { ctx in
            let request = SearchHistoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "keyword == %@ AND tabContext == %@", kw, tab.rawValue)
            request.fetchLimit = 1
            if let existing = try ctx.fetch(request).first {
                existing.searchedAt = Date()
            } else {
                let count = (try? ctx.count(for: {
                    let r = SearchHistoryEntity.fetchRequest()
                    r.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                    return r
                }())) ?? 0
                if count >= 10 {
                    let oldReq = SearchHistoryEntity.fetchRequest()
                    oldReq.predicate = NSPredicate(format: "tabContext == %@", tab.rawValue)
                    oldReq.sortDescriptors = [NSSortDescriptor(key: "searchedAt", ascending: true)]
                    oldReq.fetchLimit = 1
                    if let oldest = try ctx.fetch(oldReq).first { ctx.delete(oldest) }
                }
                let entity = SearchHistoryEntity(context: ctx)
                entity.id = UUID()
                entity.keyword = kw
                entity.tabContext = tab.rawValue
                entity.searchedAt = Date()
            }
        }
    }

    func deleteHistory(id: UUID) async {
        try? await stack.performBackground { ctx in
            let request = SearchHistoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let entity = try ctx.fetch(request).first { ctx.delete(entity) }
        }
    }

    func clearHistory() async {
        log.info("清除搜索历史")
        try? await stack.performBackground { ctx in
            let request = SearchHistoryEntity.fetchRequest()
            let all = try ctx.fetch(request)
            all.forEach { ctx.delete($0) }
        }
    }
}

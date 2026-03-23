import Foundation
@testable import TuneHaven

// MARK: - Mock API Clients

final class MockLRCLibAPIClient: LRCLibAPIClientProtocol {
    var getResult: LRCLibTrack?
    var searchResults: [LRCLibTrack] = []

    func get(trackName: String, artistName: String, albumName: String, duration: Int) async throws -> LRCLibTrack? {
        getResult
    }
    func search(trackName: String, artistName: String?) async throws -> [LRCLibTrack] {
        searchResults
    }
}

// MARK: - Mock Repositories

final class MockSearchHistoryRepository: SearchHistoryRepository {
    private var tabHistory: [LibraryTab: [SearchHistoryItem]] = [:]

    var history: [SearchHistoryItem] {
        tabHistory.values.flatMap { $0 }
    }

    func fetchHistory(tab: LibraryTab, limit: Int) async -> [SearchHistoryItem] {
        Array((tabHistory[tab] ?? []).prefix(limit))
    }
    func saveHistory(keyword: String, tab: LibraryTab) async {
        let item = SearchHistoryItem(id: UUID(), keyword: keyword, searchedAt: Date())
        tabHistory[tab, default: []].append(item)
    }
    func deleteHistory(id: UUID) async {
        for tab in tabHistory.keys {
            tabHistory[tab]?.removeAll { $0.id == id }
        }
    }
    func clearHistory() async { tabHistory.removeAll() }
    func clearHistory(tab: LibraryTab) async {
        tabHistory[tab] = nil
    }
}

final class MockSongRepository: SongRepository {
    var songs: [Song] = []

    func fetchAll(sortBy: SongSortOption, ascending: Bool) async -> [Song] { songs }
    func fetchSong(id: UUID) async -> Song? { songs.first { $0.id == id } }
    func fetchByHash(_ hash: String) async -> Song? { songs.first { $0.fileHash == hash } }
    func fetchSongs(byIds ids: [UUID]) async -> [Song] { songs.filter { ids.contains($0.id) } }
    func fetchSongs(byArtist artist: String, sortBy: SongSortOption, ascending: Bool) async -> [Song] {
        songs.filter { $0.artist == artist }
    }
    func fetchSongs(byAlbum album: String, artist: String, sortBy: SongSortOption, ascending: Bool) async -> [Song] {
        songs.filter { $0.album == album && $0.artist == artist }
    }
    func insert(song: Song) async throws { songs.append(song) }
    func softDelete(ids: [UUID]) async throws -> UndoToken {
        UndoToken(songIds: ids, movedFiles: [], expiresAt: Date().addingTimeInterval(30))
    }
    func undoDelete(token: UndoToken) async throws {}
    func commitDelete(token: UndoToken) async throws {}
    func toggleFavorite(id: UUID) async throws {}
    func recordPlay(id: UUID) async throws {}
    func updateLyrics(songId: UUID, lyricsPath: String?, lyricsSource: LyricsSource?) async throws {}
    func updateSongInfo(id: UUID, title: String, artist: String, album: String) async throws {}
    func countReferences(toFileHash hash: String) async -> Int { 0 }
    func cleanupPendingDeletes() async {}
    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int) async -> PagedResult<Song> {
        PagedResult(items: [], totalCount: 0, hasMore: false)
    }
    func fetchArtistGroups() async -> [ArtistGroup] { [] }
    func fetchAlbumGroups() async -> [AlbumGroup] { [] }
}

final class MockPlaylistRepository: PlaylistRepository {
    func fetchAll() async -> [Playlist] { [] }
    func fetchPlaylistDetail(id: UUID) async -> PlaylistDetail? { nil }
    func create(name: String, description: String?) async throws -> Playlist {
        Playlist(id: UUID(), name: name, description: description, isSystem: false,
                 systemType: .normal, songCount: 0, sortOrder: 0,
                 autoCoverPath: nil, autoCoverHash: nil, customCoverPath: nil,
                 createdAt: Date(), updatedAt: Date())
    }
    func update(id: UUID, name: String?, description: String?) async throws {}
    func delete(id: UUID) async throws {}
    func addSongs(_ songIds: [UUID], to playlistId: UUID) async throws {}
    func removeSongs(_ songIds: [UUID], from playlistId: UUID) async throws {}
    func reorder(orderedIds: [UUID]) async throws {}
    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws {}
    func createSystemPlaylists() async throws {}
    func fetchFavoritesSongIds() async -> [UUID] { [] }
    func updateAutoCover(playlistId: UUID, path: String, hash: String) async throws {}
    func setCustomCover(playlistId: UUID, imagePath: String) async throws {}
}

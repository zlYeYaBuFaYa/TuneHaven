import Foundation

/// 歌曲仓储协议 — Domain 层抽象，Data 层提供具体实现
protocol SongRepository: AnyObject {
    func fetchAll(sortBy: SongSortOption, ascending: Bool) async -> [Song]
    func fetchSong(id: UUID) async -> Song?
    func fetchByHash(_ hash: String) async -> Song?
    func fetchSongs(byIds ids: [UUID]) async -> [Song]
    func fetchSongs(byArtist artist: String, sortBy: SongSortOption, ascending: Bool) async -> [Song]
    func fetchSongs(byAlbum album: String, artist: String, sortBy: SongSortOption, ascending: Bool) async -> [Song]
    func insert(song: Song) async throws
    func softDelete(ids: [UUID]) async throws -> UndoToken
    func undoDelete(token: UndoToken) async throws
    func commitDelete(token: UndoToken) async throws
    func toggleFavorite(id: UUID) async throws
    func recordPlay(id: UUID) async throws
    func updateLyrics(songId: UUID, lyricsPath: String?, lyricsSource: LyricsSource?) async throws
    func updateCoverPath(songId: UUID, coverImagePath: String?) async throws
    func updateSongInfo(id: UUID, title: String, artist: String, album: String) async throws
    func countReferences(toFileHash hash: String) async -> Int
    func cleanupPendingDeletes() async
    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int) async -> PagedResult<Song>
    func fetchArtistGroups() async -> [ArtistGroup]
    func fetchAlbumGroups() async -> [AlbumGroup]
}

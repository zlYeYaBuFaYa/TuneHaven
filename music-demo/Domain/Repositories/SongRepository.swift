import Foundation

/// 歌曲仓储协议（TDD §1.2 Domain/Repositories）
protocol SongRepository {
    func fetchAll(sortBy: SongSortOption, ascending: Bool) async -> [Song]
    func fetchSong(id: UUID) async -> Song?
    func fetchByHash(_ hash: String) async -> Song?
    func fetchByArtist() async -> [ArtistGroup]
    func fetchByAlbum() async -> [AlbumGroup]
    func fetchArtistDetail(artist: String) async -> ArtistDetail
    func fetchAlbumDetail(album: String, artist: String) async -> AlbumDetail
    func fetchFavorites() async -> [Song]
    func fetchFiltered(format: AudioFormat?) async -> [Song]
    func create(_ song: Song) async throws
    func update(_ song: Song) async throws
    func toggleFavorite(id: UUID) async throws
    func softDelete(ids: [UUID]) async throws -> UndoToken
    func undoDelete(token: UndoToken) async throws
    func commitDelete(token: UndoToken) async throws
    func cleanupExpiredDeletes() async
    func countReferences(toFileHash hash: String) async -> Int
    func recordPlay(songId: UUID) async throws
}

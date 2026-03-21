import Foundation

/// 歌单仓储协议 — Domain 层抽象，Data 层提供具体实现
protocol PlaylistRepository: AnyObject {
    func fetchAll() async -> [Playlist]
    func fetchPlaylistDetail(id: UUID) async -> PlaylistDetail?
    func create(name: String, description: String?) async throws -> Playlist
    func update(id: UUID, name: String?, description: String?) async throws
    func delete(id: UUID) async throws
    func addSongs(_ songIds: [UUID], to playlistId: UUID) async throws
    func removeSongs(_ songIds: [UUID], from playlistId: UUID) async throws
    func reorder(orderedIds: [UUID]) async throws
    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws
    func createSystemPlaylists() async throws
    func fetchFavoritesSongIds() async -> [UUID]
    func updateAutoCover(playlistId: UUID, path: String, hash: String) async throws
    func setCustomCover(playlistId: UUID, imagePath: String) async throws
}

import Foundation

/// 歌单仓储协议（TDD §1.2 Domain/Repositories）
protocol PlaylistRepository {
    func fetchAll() async -> [Playlist]
    func fetchDetail(playlistId: UUID) async -> PlaylistDetail?
    func create(name: String, description: String?) async throws -> Playlist
    func update(id: UUID, name: String?, description: String?) async throws
    func delete(id: UUID) async throws
    func setCustomCover(playlistId: UUID, imageData: Data) async throws
    func reorder(orderedIds: [UUID]) async throws
    func addSongs(_ songIds: [UUID], to playlistId: UUID) async throws
    func removeSongs(_ songIds: [UUID], from playlistId: UUID) async throws
    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws
    func fetchFavorites() async -> [Song]
    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int) async -> PagedResult<Song>
    func createSystemPlaylists() async throws
    func regenerateAutoCover(playlistId: UUID) async throws
}

// PagedResult 已在 Domain/Entities/Playlist.swift 中定义

import Foundation

/// 歌单分组仓储协议（TDD §1.2 Domain/Repositories）
protocol PlaylistGroupRepository {
    func fetchAll() async -> [PlaylistGroup]
    func fetchGroupDetails() async -> [PlaylistGroupDetail]
    func create(name: String) async throws -> PlaylistGroup
    func rename(id: UUID, name: String) async throws
    func delete(id: UUID) async throws
    func movePlaylist(_ playlistId: UUID, toGroup groupId: UUID?) async throws
    func reorder(orderedIds: [UUID]) async throws
}

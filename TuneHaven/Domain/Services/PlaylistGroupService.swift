import Foundation

/// 歌单分组服务（TDD Section 3.4）
@MainActor
final class PlaylistGroupService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var groupDetails: [PlaylistGroupDetail] = []

    private let repo: PlaylistGroupRepository

    init(repo: PlaylistGroupRepository) {
        self.repo = repo
    }

    func loadGroups() async {
        groupDetails = await repo.fetchGroupDetails()
    }

    /// 创建分组
    func createGroup(name: String) async throws -> PlaylistGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.playlistNameEmpty }
        log.info("创建歌单分组: \(trimmed)")
        let group = try await repo.create(name: trimmed)
        await loadGroups()
        return group
    }

    /// 重命名分组
    func renameGroup(id: UUID, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.playlistNameEmpty }
        try await repo.rename(id: id, name: trimmed)
        await loadGroups()
    }

    /// 删除分组（歌单 groupId 置 nil，不删除歌单）
    func deleteGroup(id: UUID) async throws {
        log.info("删除歌单分组: \(id)")
        try await repo.delete(id: id)
        await loadGroups()
    }

    /// 将歌单移入/移出分组
    func movePlaylist(_ playlistId: UUID, toGroup groupId: UUID?) async throws {
        try await repo.movePlaylist(playlistId, toGroup: groupId)
        await loadGroups()
    }

    /// 调整分组排序
    func reorderGroups(orderedIds: [UUID]) async throws {
        try await repo.reorder(orderedIds: orderedIds)
        await loadGroups()
    }
}

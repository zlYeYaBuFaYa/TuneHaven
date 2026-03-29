import Foundation

/// 同步数据仓储协议 — 管理缺失歌曲引用的持久化
protocol SyncRepository: AnyObject {
    func fetchAllMissingReferences() async -> [MissingSongReference]
    func fetchMissingReferences(forPlaylist playlistId: UUID) async -> [MissingSongReference]
    func insertMissingReference(_ reference: MissingSongReference) async throws
    func insertMissingReferences(_ references: [MissingSongReference]) async throws
    func deleteMissingReference(id: UUID) async throws
    func deleteMissingReferences(ids: [UUID]) async throws
    func deleteMissingReferences(forPlaylist playlistId: UUID) async throws
}

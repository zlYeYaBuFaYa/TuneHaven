import CoreData
import Foundation

final class CoreDataPlaylistGroupRepository: PlaylistGroupRepository {
    private let stack: CoreDataStack
    private let log = AppLogger.shared
    init(stack: CoreDataStack = .shared) { self.stack = stack }

    func fetchAll() async -> [PlaylistGroup] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = PlaylistGroupEntity.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                let results: [PlaylistGroupEntity]
                do {
                    results = try self.stack.viewContext.fetch(request)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "PlaylistGroup.fetchAll")
                    log.error(error, context: "PlaylistGroup.fetchAll 查询失败")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: results.compactMap { entity -> PlaylistGroup? in
                    guard let id = entity.id, let name = entity.name, let created = entity.createdAt else { return nil }
                    return PlaylistGroup(id: id, name: name, createdAt: created, sortOrder: Int(entity.sortOrder))
                })
            }
        }
    }

    func create(name: String) async throws -> PlaylistGroup {
        try await stack.performBackground { ctx in
            let entity = PlaylistGroupEntity(context: ctx)
            entity.id = UUID()
            entity.name = name
            entity.createdAt = Date()
            let maxReq: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "PlaylistGroupEntity")
            maxReq.resultType = .dictionaryResultType
            let expr = NSExpression(forKeyPath: "sortOrder")
            let maxExpr = NSExpression(forFunction: "max:", arguments: [expr])
            let desc = NSExpressionDescription()
            desc.name = "maxSortOrder"
            desc.expression = maxExpr
            desc.expressionResultType = .integer32AttributeType
            maxReq.propertiesToFetch = [desc]
            let maxResult = (try? ctx.fetch(maxReq))?.first?["maxSortOrder"] as? Int32 ?? -1
            entity.sortOrder = maxResult + 1
            guard let id = entity.id, let createdAt = entity.createdAt else {
                throw AppError.databaseError(NSError(domain: "CoreDataPlaylistGroupRepository", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "创建分组后属性为空"]))
            }
            return PlaylistGroup(id: id, name: name, createdAt: createdAt, sortOrder: Int(entity.sortOrder))
        }
    }

    func rename(id: UUID, name: String) async throws {
        try await stack.performBackground { [log] ctx in
            let request = PlaylistGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                log.debug("rename group: entity not found id=\(id)")
                return
            }
            entity.name = name
        }
    }

    func delete(id: UUID) async throws {
        try await stack.performBackground { ctx in
            // 先把该分组下的歌单 groupId 置 nil
            let playlistReq = PlaylistEntity.fetchRequest()
            playlistReq.predicate = NSPredicate(format: "groupId == %@", id as CVarArg)
            let playlists = try ctx.fetch(playlistReq)
            playlists.forEach { $0.groupId = nil }

            let groupReq = PlaylistGroupEntity.fetchRequest()
            groupReq.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            groupReq.fetchLimit = 1
            if let entity = try ctx.fetch(groupReq).first { ctx.delete(entity) }
        }
    }

    func movePlaylist(_ playlistId: UUID, toGroup groupId: UUID?) async throws {
        try await stack.performBackground { [log] ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", playlistId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                log.debug("movePlaylist: entity not found id=\(playlistId)")
                return
            }
            entity.groupId = groupId
        }
    }

    func reorder(orderedIds: [UUID]) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", orderedIds as NSArray)
            let groups = try ctx.fetch(request)
            let idToGroup = Dictionary(uniqueKeysWithValues: groups.compactMap { g -> (UUID, PlaylistGroupEntity)? in
                guard let id = g.id else { return nil }
                return (id, g)
            })
            for (i, id) in orderedIds.enumerated() {
                idToGroup[id]?.sortOrder = Int32(i)
            }
        }
    }

    func fetchGroupDetails() async -> [PlaylistGroupDetail] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let groupRequest = PlaylistGroupEntity.fetchRequest()
                groupRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                groupRequest.fetchBatchSize = 50
                let groups: [PlaylistGroupEntity]
                do {
                    groups = try self.stack.viewContext.fetch(groupRequest)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchGroupDetails: groups")
                    log.error(error, context: "fetchGroupDetails groups 查询失败")
                    continuation.resume(returning: [])
                    return
                }

                let playlistRequest = PlaylistEntity.fetchRequest()
                playlistRequest.fetchBatchSize = 50
                let playlists: [PlaylistEntity]
                do {
                    playlists = try self.stack.viewContext.fetch(playlistRequest)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchGroupDetails: playlists")
                    log.error(error, context: "fetchGroupDetails playlists 查询失败")
                    continuation.resume(returning: [])
                    return
                }

                let details = groups.compactMap { group -> PlaylistGroupDetail? in
                    guard let id = group.id, let name = group.name else { return nil }
                    let groupPlaylists = playlists
                        .filter { $0.groupId == id }
                        .compactMap { PlaylistMapper.toDomain($0) }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    let totalSongs = groupPlaylists.reduce(0) { $0 + $1.songCount }
                    return PlaylistGroupDetail(id: id, name: name, playlists: groupPlaylists, totalSongCount: totalSongs)
                }
                continuation.resume(returning: details)
            }
        }
    }
}

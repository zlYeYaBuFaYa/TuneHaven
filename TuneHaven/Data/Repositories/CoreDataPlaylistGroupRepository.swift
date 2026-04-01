import CoreData
import Foundation

final class CoreDataPlaylistGroupRepository: PlaylistGroupRepository, @unchecked Sendable {
    private let stack: CoreDataStack
    private let log = AppLogger.shared
    init(stack: CoreDataStack = .shared) { self.stack = stack }

    func fetchAll() async -> [PlaylistGroup] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = PlaylistGroupEntity.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                let results: [PlaylistGroupEntity]
                do {
                    results = try self.stack.viewContext.fetch(request)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "PlaylistGroup.fetchAll")
                    self.log.error(error, context: "PlaylistGroup.fetchAll 查询失败")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: results.compactMap { PlaylistGroupMapper.toDomain($0) })
            }
        }
    }

    func create(name: String) async throws -> PlaylistGroup {
        try await stack.performBackground { ctx in
            let entity = PlaylistGroupEntity(context: ctx)
            let id = UUID()
            let createdAt = Date()
            entity.id = id
            entity.name = name
            entity.createdAt = createdAt
            let maxOrder = (try? ctx.maxSortOrder(forEntity: "PlaylistGroupEntity")) ?? 0
            entity.sortOrder = Int32(maxOrder + 1)
            return PlaylistGroup(id: id, name: name, createdAt: createdAt, sortOrder: Int(entity.sortOrder))
        }
    }

    func rename(id: UUID, name: String) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("rename group: entity not found id=\(id)")
                return
            }
            entity.name = name
        }
    }

    func delete(id: UUID) async throws {
        try await stack.performBackground { ctx in
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
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", playlistId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("movePlaylist: entity not found id=\(playlistId)")
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
            stack.viewContext.perform {
                let groupRequest = PlaylistGroupEntity.fetchRequest()
                groupRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                groupRequest.fetchBatchSize = 50
                let groups: [PlaylistGroupEntity]
                do {
                    groups = try self.stack.viewContext.fetch(groupRequest)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchGroupDetails: groups")
                    self.log.error(error, context: "fetchGroupDetails groups 查询失败")
                    continuation.resume(returning: [])
                    return
                }

                let playlistRequest = PlaylistEntity.fetchRequest()
                playlistRequest.predicate = NSPredicate(format: "groupId != nil")
                playlistRequest.fetchBatchSize = 50
                let playlists: [PlaylistEntity]
                do {
                    playlists = try self.stack.viewContext.fetch(playlistRequest)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchGroupDetails: playlists")
                    self.log.error(error, context: "fetchGroupDetails playlists 查询失败")
                    continuation.resume(returning: [])
                    return
                }

                let songCountMap: [UUID: Int]
                do {
                    songCountMap = try self.batchPlaylistSongCounts(context: self.stack.viewContext, playlists: playlists)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchGroupDetails: songCounts")
                    self.log.error(error, context: "fetchGroupDetails songCounts 查询失败")
                    songCountMap = [:]
                }

                let details = groups.compactMap { group -> PlaylistGroupDetail? in
                    guard let id = group.id, let name = group.name else { return nil }
                    let groupPlaylists = playlists
                        .filter { $0.groupId == id }
                        .compactMap { entity -> Playlist? in
                            guard let pid = entity.id else { return nil }
                            return PlaylistMapper.toDomain(entity, songCount: songCountMap[pid] ?? 0)
                        }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    let totalSongs = groupPlaylists.reduce(0) { $0 + $1.songCount }
                    return PlaylistGroupDetail(id: id, name: name, playlists: groupPlaylists, totalSongCount: totalSongs)
                }
                continuation.resume(returning: details)
            }
        }
    }

    // MARK: - Private Helpers

    private func batchPlaylistSongCounts(context: NSManagedObjectContext, playlists: [PlaylistEntity]) throws -> [UUID: Int] {
        let playlistIds = playlists.compactMap { $0.id }
        guard !playlistIds.isEmpty else { return [:] }

        let deletedIds = try context.softDeletedSongIds()

        let countReq: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "PlaylistSongEntity")
        countReq.resultType = .dictionaryResultType
        if deletedIds.isEmpty {
            countReq.predicate = NSPredicate(format: "playlistId IN %@", playlistIds as NSArray)
        } else {
            countReq.predicate = NSPredicate(format: "playlistId IN %@ AND NOT (songId IN %@)", playlistIds as NSArray, deletedIds as NSArray)
        }
        let countExpr = NSExpressionDescription()
        countExpr.name = "count"
        countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "songId")])
        countExpr.expressionResultType = .integer64AttributeType
        countReq.propertiesToFetch = ["playlistId", countExpr]
        countReq.propertiesToGroupBy = ["playlistId"]
        let countResults = try context.fetch(countReq)
        var countMap: [UUID: Int] = [:]
        for result in countResults {
            if let pid = result["playlistId"] as? UUID, let count = result["count"] as? Int {
                countMap[pid] = count
            }
        }
        return countMap
    }

}

import CoreData
import Foundation

final class CoreDataPlaylistRepository: PlaylistRepository {
    private let stack: CoreDataStack
    private let log = AppLogger.shared
    init(stack: CoreDataStack = .shared) { self.stack = stack }

    func fetchAll() async -> [Playlist] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                self.stack.viewContext.processPendingChanges()
                let request = PlaylistEntity.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                request.returnsObjectsAsFaults = false
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    let songCountMap = try self.batchSongCounts(context: self.stack.viewContext, playlists: results)
                    let playlists = results.compactMap { entity -> Playlist? in
                        guard let id = entity.id else { return nil }
                        return PlaylistMapper.toDomain(entity, songCount: songCountMap[id] ?? 0)
                    }
                    continuation.resume(returning: playlists)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "Playlist.fetchAll")
                    self.log.error(error, context: "Playlist.fetchAll 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchPlaylistDetail(id: UUID) async -> PlaylistDetail? {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                do {
                    guard let entity = try self.fetchPlaylistEntity(id: id, context: self.stack.viewContext) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let songCount = try self.computeSongCount(entity: entity, id: id, context: self.stack.viewContext)
                    guard let playlist = PlaylistMapper.toDomain(entity, songCount: songCount) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let songs = try self.fetchLinkedSongs(playlistId: id, context: self.stack.viewContext)
                    continuation.resume(returning: PlaylistDetail(playlist: playlist, songs: songs))
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchPlaylistDetail id=\(id)")
                    self.log.error(error, context: "fetchPlaylistDetail 查询失败")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func create(name: String, description: String?) async throws -> Playlist {
        try await stack.performBackground { ctx in
            let entity = PlaylistEntity(context: ctx)
            entity.id = UUID()
            entity.name = name
            entity.desc_ = description
            entity.isSystem = false
            entity.systemType = 0
            entity.createdAt = Date()
            entity.updatedAt = Date()
            let maxOrder = try ctx.maxSortOrder(forEntity: "PlaylistEntity",
                                                predicate: NSPredicate(format: "isSystem == NO"))
            entity.sortOrder = Int32(maxOrder + 1)
            guard let playlist = PlaylistMapper.toDomain(entity, songCount: 0) else {
                throw AppError.databaseError(NSError(domain: "", code: -1))
            }
            return playlist
        }
    }

    func update(id: UUID, name: String?, description: String?) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("update playlist: entity not found id=\(id)")
                return
            }
            if let name { entity.name = name }
            if let description { entity.desc_ = description }
            entity.updatedAt = Date()
        }
    }

    func delete(id: UUID) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND isSystem == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("delete playlist: entity not found id=\(id)")
                return
            }

            let psReq = PlaylistSongEntity.fetchRequest()
            psReq.predicate = NSPredicate(format: "playlistId == %@", id as CVarArg)
            let links = try ctx.fetch(psReq)
            links.forEach { ctx.delete($0) }

            ctx.delete(entity)
        }
    }

    func addSongs(_ songIds: [UUID], to playlistId: UUID) async throws {
        try await stack.performBackground { ctx in
            let existRequest = PlaylistSongEntity.fetchRequest()
            existRequest.predicate = NSPredicate(format: "playlistId == %@", playlistId as CVarArg)
            existRequest.propertiesToFetch = ["songId", "sortOrder"]
            let existing = try ctx.fetch(existRequest)
            let existingIds = Set(existing.compactMap { $0.songId })

            let maxOrderReq = PlaylistSongEntity.fetchRequest()
            maxOrderReq.predicate = NSPredicate(format: "playlistId == %@", playlistId as CVarArg)
            maxOrderReq.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
            maxOrderReq.fetchLimit = 1
            maxOrderReq.propertiesToFetch = ["sortOrder"]
            let maxOrder = (try? ctx.fetch(maxOrderReq))?.first?.sortOrder ?? -1

            var addedCount: Int32 = 0
            for songId in songIds {
                guard !existingIds.contains(songId) else { continue }
                addedCount += 1
                let link = PlaylistSongEntity(context: ctx)
                link.playlistId = playlistId
                link.songId = songId
                link.sortOrder = maxOrder + addedCount
                link.addedAt = Date()
            }

            let playlistRequest = PlaylistEntity.fetchRequest()
            playlistRequest.predicate = NSPredicate(format: "id == %@", playlistId as CVarArg)
            playlistRequest.fetchLimit = 1
            try ctx.fetch(playlistRequest).first?.updatedAt = Date()
        }
    }

    func removeSongs(_ songIds: [UUID], from playlistId: UUID) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistSongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "playlistId == %@ AND songId IN %@",
                playlistId as CVarArg, songIds as NSArray)
            let links = try ctx.fetch(request)
            links.forEach { ctx.delete($0) }

            let playlistRequest = PlaylistEntity.fetchRequest()
            playlistRequest.predicate = NSPredicate(format: "id == %@", playlistId as CVarArg)
            playlistRequest.fetchLimit = 1
            try ctx.fetch(playlistRequest).first?.updatedAt = Date()
        }
    }

    func updateAutoCover(playlistId: UUID, path: String, hash: String) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", playlistId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("updateAutoCover: entity not found id=\(playlistId)")
                return
            }
            entity.autoCoverPath = path
            entity.autoCoverHash = hash
        }
    }

    func setCustomCover(playlistId: UUID, imagePath: String) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", playlistId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("setCustomCover: entity not found id=\(playlistId)")
                return
            }
            entity.customCoverPath = imagePath
        }
    }

    func reorder(orderedIds: [UUID]) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "isSystem == NO")
            let entities = try ctx.fetch(request)
            let idToEntity = Dictionary(uniqueKeysWithValues: entities.compactMap { e -> (UUID, PlaylistEntity)? in
                guard let id = e.id else { return nil }
                return (id, e)
            })
            for (i, id) in orderedIds.enumerated() {
                if idToEntity[id] == nil {
                    self.log.debug("reorder: 未找到歌单 id=\(id)，跳过")
                }
                idToEntity[id]?.sortOrder = Int32(i)
            }
        }
    }

    func reorderSongs(in playlistId: UUID, orderedSongIds: [UUID]) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistSongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "playlistId == %@", playlistId as CVarArg)
            let links = try ctx.fetch(request)
            let idToLink = Dictionary(uniqueKeysWithValues: links.compactMap { l -> (UUID, PlaylistSongEntity)? in
                guard let sid = l.songId else { return nil }
                return (sid, l)
            })
            for (i, songId) in orderedSongIds.enumerated() {
                if idToLink[songId] == nil {
                    self.log.debug("reorderSongs: 未找到歌曲链接 songId=\(songId) in playlist=\(playlistId)")
                }
                idToLink[songId]?.sortOrder = Int32(i)
            }
        }
    }

    func createSystemPlaylists() async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "isSystem == YES")
            let existing = try ctx.fetch(request)
            let existingTypes = Set(existing.map { $0.systemType })

            if !existingTypes.contains(SystemPlaylistType.favorites.rawValue) {
                let favorites = PlaylistEntity(context: ctx)
                favorites.id = UUID()
                favorites.name = SystemPlaylistName.favorites
                favorites.isSystem = true
                favorites.systemType = SystemPlaylistType.favorites.rawValue
                favorites.sortOrder = -2
                favorites.createdAt = Date()
                favorites.updatedAt = Date()
            }
            if !existingTypes.contains(SystemPlaylistType.recentlyPlayed.rawValue) {
                let recent = PlaylistEntity(context: ctx)
                recent.id = UUID()
                recent.name = SystemPlaylistName.recentlyPlayed
                recent.isSystem = true
                recent.systemType = SystemPlaylistType.recentlyPlayed.rawValue
                recent.sortOrder = -1
                recent.createdAt = Date()
                recent.updatedAt = Date()
            }
        }
    }

    func fetchFavoritesSongIds() async -> [UUID] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "SongEntity")
                request.resultType = .dictionaryResultType
                request.predicate = NSPredicate(format: "isFavorite == YES AND softDeleted == NO")
                request.sortDescriptors = [NSSortDescriptor(key: "favoriteDate", ascending: false)]
                request.propertiesToFetch = ["id"]
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: results.compactMap { $0["id"] as? UUID })
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchFavoritesSongIds")
                    self.log.error(error, context: "fetchFavoritesSongIds 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func fetchPlaylistEntity(id: UUID, context: NSManagedObjectContext) throws -> PlaylistEntity? {
        let request = PlaylistEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchLinkedSongs(playlistId: UUID, context: NSManagedObjectContext) throws -> [Song] {
        let psRequest = PlaylistSongEntity.fetchRequest()
        psRequest.predicate = NSPredicate(format: "playlistId == %@", playlistId as CVarArg)
        psRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        psRequest.fetchBatchSize = 50
        let links = try context.fetch(psRequest)
        let songIds = links.compactMap { $0.songId }
        guard !songIds.isEmpty else { return [] }

        let songRequest = SongEntity.fetchRequest()
        songRequest.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", songIds as NSArray)
        let songEntities = try context.fetch(songRequest)
        let idToSong = Dictionary(uniqueKeysWithValues: songEntities.compactMap { e -> (UUID, Song)? in
            guard let id = e.id, let s = SongMapper.toDomain(e) else { return nil }
            return (id, s)
        })
        return songIds.compactMap { idToSong[$0] }
    }

    private func computeSongCount(entity: PlaylistEntity, id: UUID, context: NSManagedObjectContext) throws -> Int {
        if entity.isSystem {
            let systemType = SystemPlaylistType(rawValue: entity.systemType) ?? .normal
            switch systemType {
            case .favorites:
                let req = SongEntity.fetchRequest()
                req.predicate = NSPredicate(format: "isFavorite == YES AND softDeleted == NO")
                return try context.count(for: req)
            case .recentlyPlayed:
                let req = SongEntity.fetchRequest()
                req.predicate = NSPredicate(format: "lastPlayedDate != nil AND softDeleted == NO")
                return try context.count(for: req)
            default:
                return 0
            }
        } else {
            let req = PlaylistSongEntity.fetchRequest()
            req.predicate = NSPredicate(format: "playlistId == %@", id as CVarArg)
            req.includesSubentities = false
            req.includesPropertyValues = false
            return try context.count(for: req)
        }
    }

    private func batchSongCounts(context: NSManagedObjectContext, playlists: [PlaylistEntity]) throws -> [UUID: Int] {
        var countMap: [UUID: Int] = [:]

        let countReq: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "PlaylistSongEntity")
        countReq.resultType = .dictionaryResultType
        let countExpr = NSExpressionDescription()
        countExpr.name = "count"
        countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "songId")])
        countExpr.expressionResultType = .integer64AttributeType
        countReq.propertiesToFetch = ["playlistId", countExpr]
        countReq.propertiesToGroupBy = ["playlistId"]
        let countResults = try context.fetch(countReq)
        for result in countResults {
            if let pid = result["playlistId"] as? UUID, let count = result["count"] as? Int {
                countMap[pid] = count
            }
        }

        for entity in playlists where entity.isSystem {
            guard let id = entity.id else { continue }
            countMap[id] = try computeSongCount(entity: entity, id: id, context: context)
        }

        return countMap
    }
}

// MARK: - Shared maxSortOrder utility

extension NSManagedObjectContext {
    func maxSortOrder(forEntity entityName: String, predicate: NSPredicate? = nil) throws -> Int {
        let request: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        let expr = NSExpression(forKeyPath: "sortOrder")
        let maxExpr = NSExpression(forFunction: "max:", arguments: [expr])
        let desc = NSExpressionDescription()
        desc.name = "maxSortOrder"
        desc.expression = maxExpr
        desc.expressionResultType = .integer32AttributeType
        request.propertiesToFetch = [desc]
        let results = try self.fetch(request)
        return (results.first?["maxSortOrder"] as? Int) ?? 0
    }
}

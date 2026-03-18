import CoreData
import Foundation

final class CoreDataPlaylistRepository {
    private let stack: CoreDataStack
    init(stack: CoreDataStack = .shared) { self.stack = stack }

    func fetchAll() async -> [Playlist] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                self.stack.viewContext.refreshAllObjects()
                let request = PlaylistEntity.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                request.fetchBatchSize = 50
                let results = (try? self.stack.viewContext.fetch(request)) ?? []
                continuation.resume(returning: results.compactMap { PlaylistMapper.toDomain($0) })
            }
        }
    }

    func fetchPlaylistDetail(id: UUID) async -> PlaylistDetail? {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = PlaylistEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                guard let entity = try? self.stack.viewContext.fetch(request).first,
                      let playlist = PlaylistMapper.toDomain(entity) else {
                    continuation.resume(returning: nil)
                    return
                }

                let psRequest = PlaylistSongEntity.fetchRequest()
                psRequest.predicate = NSPredicate(format: "playlistId == %@", id as CVarArg)
                psRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                psRequest.fetchBatchSize = 50
                let links = (try? self.stack.viewContext.fetch(psRequest)) ?? []
                let songIds = links.compactMap { $0.songId }

                let songRequest = SongEntity.fetchRequest()
                songRequest.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", songIds as NSArray)
                let songEntities = (try? self.stack.viewContext.fetch(songRequest)) ?? []
                let idToSong = Dictionary(uniqueKeysWithValues: songEntities.compactMap { e -> (UUID, Song)? in
                    guard let id = e.id, let s = SongMapper.toDomain(e) else { return nil }
                    return (id, s)
                })
                let songs = songIds.compactMap { idToSong[$0] }
                continuation.resume(returning: PlaylistDetail(playlist: playlist, songs: songs))
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
            let maxOrder = try self.maxSortOrder(ctx: ctx)
            entity.sortOrder = Int32(maxOrder + 1)
            guard let playlist = PlaylistMapper.toDomain(entity) else {
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
            guard let entity = try ctx.fetch(request).first else { return }
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
            guard let entity = try ctx.fetch(request).first else { return }

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
            let existing = try ctx.fetch(existRequest)
            let existingIds = Set(existing.compactMap { $0.songId })
            let maxOrder = existing.map { $0.sortOrder }.max() ?? -1

            for (i, songId) in songIds.enumerated() {
                guard !existingIds.contains(songId) else { continue }
                let link = PlaylistSongEntity(context: ctx)
                link.playlistId = playlistId
                link.songId = songId
                link.sortOrder = maxOrder + Int32(i + 1)
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
            guard let entity = try ctx.fetch(request).first else { return }
            entity.autoCoverPath = path
            entity.autoCoverHash = hash
        }
    }

    func setCustomCover(playlistId: UUID, imagePath: String) async throws {
        try await stack.performBackground { ctx in
            let request = PlaylistEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", playlistId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else { return }
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
                idToEntity[id]?.sortOrder = Int32(i)
            }
        }
    }

    /// 调整歌单内歌曲排序（TDD Section 3.3）
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

            if !existingTypes.contains(1) {
                let favorites = PlaylistEntity(context: ctx)
                favorites.id = UUID()
                favorites.name = "我喜欢"
                favorites.isSystem = true
                favorites.systemType = 1
                favorites.sortOrder = -2
                favorites.createdAt = Date()
                favorites.updatedAt = Date()
            }
            if !existingTypes.contains(2) {
                let recent = PlaylistEntity(context: ctx)
                recent.id = UUID()
                recent.name = "最近播放"
                recent.isSystem = true
                recent.systemType = 2
                recent.sortOrder = -1
                recent.createdAt = Date()
                recent.updatedAt = Date()
            }
        }
    }

    func fetchFavoritesSongIds() async -> [UUID] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "isFavorite == YES AND softDeleted == NO")
                request.sortDescriptors = [NSSortDescriptor(key: "favoriteDate", ascending: false)]
                let results = (try? self.stack.viewContext.fetch(request)) ?? []
                continuation.resume(returning: results.compactMap { $0.id })
            }
        }
    }

    private func maxSortOrder(ctx: NSManagedObjectContext) throws -> Int {
        let request = PlaylistEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isSystem == NO")
        let entities = try ctx.fetch(request)
        return Int(entities.map { $0.sortOrder }.max() ?? 0)
    }
}

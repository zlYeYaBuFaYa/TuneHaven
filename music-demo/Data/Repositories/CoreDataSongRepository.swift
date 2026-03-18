import CoreData
import Foundation

final class CoreDataSongRepository {
    private let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    func fetchAll(sortBy: SongSortOption, ascending: Bool) async -> [Song] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "softDeleted == NO")
                request.sortDescriptors = [NSSortDescriptor(key: sortBy.coreDataKey, ascending: ascending)]
                request.fetchBatchSize = 50
                let results = (try? self.stack.viewContext.fetch(request)) ?? []
                continuation.resume(returning: results.compactMap { SongMapper.toDomain($0) })
            }
        }
    }

    func fetchSong(id: UUID) async -> Song? {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
                request.fetchLimit = 1
                let result = try? self.stack.viewContext.fetch(request)
                continuation.resume(returning: result?.first.flatMap { SongMapper.toDomain($0) })
            }
        }
    }

    func fetchByHash(_ hash: String) async -> Song? {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO", hash)
                request.fetchLimit = 1
                let result = try? self.stack.viewContext.fetch(request)
                continuation.resume(returning: result?.first.flatMap { SongMapper.toDomain($0) })
            }
        }
    }

    func countReferences(toFileHash hash: String) async -> Int {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO", hash)
                let count = (try? self.stack.viewContext.count(for: request)) ?? 0
                continuation.resume(returning: count)
            }
        }
    }

    func insert(song: Song) async throws {
        try await stack.performBackground { ctx in
            _ = SongMapper.toEntity(song, context: ctx)
        }
    }

    func softDelete(ids: [UUID]) async throws -> UndoToken {
        let now = Date()
        var movedFiles: [UndoToken.MovedFile] = []

        var filesToMove: [(hash: String, relativePath: String)] = []
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", ids as NSArray)
            let entities = try ctx.fetch(request)
            for entity in entities {
                if let hash = entity.fileHash, let path = entity.fileRelativePath {
                    let countReq = SongEntity.fetchRequest()
                    countReq.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO AND NOT (id IN %@)",
                        hash, ids as NSArray)
                    let count = (try? ctx.count(for: countReq)) ?? 0
                    if count == 0 {
                        filesToMove.append((hash: hash, relativePath: path))
                    }
                }
                entity.softDeleted = true
                entity.deletedAt = now
            }
        }

        for file in filesToMove {
            if let tmpPath = try? FileStorageService.shared.moveToPendingDelete(relativePath: file.relativePath) {
                movedFiles.append(UndoToken.MovedFile(tempPath: tmpPath, originalRelativePath: file.relativePath))
            }
        }

        return UndoToken(songIds: ids, movedFiles: movedFiles, expiresAt: now.addingTimeInterval(30))
    }

    func undoDelete(token: UndoToken) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", token.songIds as NSArray)
            let entities = try ctx.fetch(request)
            for entity in entities {
                entity.softDeleted = false
                entity.deletedAt = nil
            }
        }
        for file in token.movedFiles {
            try? FileStorageService.shared.restoreFromPendingDelete(fileName: file.tempPath, originalRelativePath: file.originalRelativePath)
        }
    }

    func commitDelete(token: UndoToken) async throws {
        try await stack.performBackground { ctx in
            let songRequest = SongEntity.fetchRequest()
            songRequest.predicate = NSPredicate(format: "id IN %@", token.songIds as NSArray)
            let songs = try ctx.fetch(songRequest)
            for song in songs {
                let psRequest = PlaylistSongEntity.fetchRequest()
                psRequest.predicate = NSPredicate(format: "songId == %@", song.id! as CVarArg)
                let links = try ctx.fetch(psRequest)
                links.forEach { ctx.delete($0) }
                ctx.delete(song)
            }
        }
        for file in token.movedFiles {
            FileStorageService.shared.deleteFromPendingDelete(fileName: file.tempPath)
        }
    }

    func toggleFavorite(id: UUID) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else { return }
            entity.isFavorite.toggle()
            entity.favoriteDate = entity.isFavorite ? Date() : nil
        }
    }

    func recordPlay(id: UUID) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else { return }
            entity.playCount += 1
            entity.lastPlayedDate = Date()

            let record = PlayRecordEntity(context: ctx)
            record.id = UUID()
            record.songId = id
            record.playedAt = Date()
        }
    }

    func cleanupPendingDeletes() async {
        try? await stack.performBackground { ctx in
            let cutoff = Date().addingTimeInterval(-30)
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "softDeleted == YES AND deletedAt < %@", cutoff as CVarArg)
            let entities = try ctx.fetch(request)
            for entity in entities {
                if let hash = entity.fileHash, let path = entity.fileRelativePath {
                    let refReq = SongEntity.fetchRequest()
                    refReq.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO", hash)
                    let count = (try? ctx.count(for: refReq)) ?? 0
                    if count == 0 {
                        let fm = FileManager.default
                        let url = SandboxPathManager.musicFileURL(relativePath: path)
                        try? fm.removeItem(at: url)
                    }
                }
                if let songId = entity.id {
                    let psReq = PlaylistSongEntity.fetchRequest()
                    psReq.predicate = NSPredicate(format: "songId == %@", songId as CVarArg)
                    let links = try ctx.fetch(psReq)
                    links.forEach { ctx.delete($0) }
                }
                ctx.delete(entity)
            }
        }
        FileStorageService.shared.cleanupPendingDeleteDirectory()
    }

    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int) async -> PagedResult<Song> {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = PlayRecordEntity.fetchRequest()
                if days > 0 {
                    let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
                    request.predicate = NSPredicate(format: "playedAt >= %@", cutoff as CVarArg)
                }
                request.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]

                let allRecords = (try? self.stack.viewContext.fetch(request)) ?? []
                var seen = Set<UUID>()
                var uniqueIds: [UUID] = []
                for record in allRecords {
                    guard let sid = record.songId, !seen.contains(sid) else { continue }
                    seen.insert(sid)
                    uniqueIds.append(sid)
                }

                let totalCount = uniqueIds.count
                let startIndex = page * pageSize
                guard startIndex < totalCount else {
                    continuation.resume(returning: PagedResult(items: [], totalCount: totalCount, currentPage: page, hasMore: false))
                    return
                }
                let pageIds = Array(uniqueIds[startIndex..<min(startIndex + pageSize, totalCount)])

                let songReq = SongEntity.fetchRequest()
                songReq.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", pageIds as NSArray)
                let songEntities = (try? self.stack.viewContext.fetch(songReq)) ?? []

                let idToSong = Dictionary(uniqueKeysWithValues: songEntities.compactMap { e -> (UUID, Song)? in
                    guard let id = e.id, let song = SongMapper.toDomain(e) else { return nil }
                    return (id, song)
                })
                let songs = pageIds.compactMap { idToSong[$0] }

                continuation.resume(returning: PagedResult(
                    items: songs,
                    totalCount: totalCount,
                    currentPage: page,
                    hasMore: startIndex + pageSize < totalCount
                ))
            }
        }
    }

    private func fetchDeletedSong(id: UUID) async -> Song? {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                let result = try? self.stack.viewContext.fetch(request)
                continuation.resume(returning: result?.first.flatMap { SongMapper.toDomain($0) })
            }
        }
    }
}

private extension SongSortOption {
    var coreDataKey: String {
        switch self {
        case .title: return "title"
        case .fileSize: return "fileSize"
        case .importDate: return "importDate"
        case .artist: return "artist"
        case .album: return "album"
        case .duration: return "duration"
        }
    }
}

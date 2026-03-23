import CoreData
import Foundation

final class CoreDataSongRepository: SongRepository {
    private let stack: CoreDataStack
    private let log = AppLogger.shared

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    func fetchAll(sortBy: SongSortOption, ascending: Bool) async -> [Song] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "softDeleted == NO")
                request.sortDescriptors = [NSSortDescriptor(key: sortBy.coreDataKey, ascending: ascending)]
                request.fetchBatchSize = 50
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: results.compactMap { SongMapper.toDomain($0) })
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchAll")
                    log.error(error, context: "fetchAll 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchSong(id: UUID) async -> Song? {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
                request.fetchLimit = 1
                do {
                    let result = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: result.first.flatMap { SongMapper.toDomain($0) })
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchSong id=\(id)")
                    log.error(error, context: "fetchSong 查询失败")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func fetchSongs(byIds ids: [UUID]) async -> [Song] {
        guard !ids.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", ids as NSArray)
                request.fetchBatchSize = 50
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: results.compactMap { SongMapper.toDomain($0) })
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchSongs(byIds:)")
                    log.error(error, context: "fetchSongs(byIds:) 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchSongs(byArtist artist: String, sortBy: SongSortOption = .album, ascending: Bool = true) async -> [Song] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "artist == %@ AND softDeleted == NO", artist)
                request.sortDescriptors = [NSSortDescriptor(key: sortBy.coreDataKey, ascending: ascending)]
                request.fetchBatchSize = 50
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: results.compactMap { SongMapper.toDomain($0) })
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchSongs(byArtist:)")
                    log.error(error, context: "fetchSongs(byArtist:) 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchSongs(byAlbum album: String, artist: String, sortBy: SongSortOption = .title, ascending: Bool = true) async -> [Song] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "album == %@ AND artist == %@ AND softDeleted == NO", album, artist)
                request.sortDescriptors = [NSSortDescriptor(key: sortBy.coreDataKey, ascending: ascending)]
                request.fetchBatchSize = 50
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: results.compactMap { SongMapper.toDomain($0) })
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchSongs(byAlbum:)")
                    log.error(error, context: "fetchSongs(byAlbum:) 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchByHash(_ hash: String) async -> Song? {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO", hash)
                request.fetchLimit = 1
                do {
                    let result = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: result.first.flatMap { SongMapper.toDomain($0) })
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchByHash")
                    log.error(error, context: "fetchByHash 查询失败")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func countReferences(toFileHash hash: String) async -> Int {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO", hash)
                do {
                    let count = try self.stack.viewContext.count(for: request)
                    continuation.resume(returning: count)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "countReferences")
                    log.error(error, context: "countReferences 查询失败")
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    func insert(song: Song) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "fileHash == %@", song.fileHash)
            request.fetchLimit = 1
            if let existing = try ctx.fetch(request).first {
                SongMapper.updateEntity(existing, from: song)
            } else {
                _ = SongMapper.toEntity(song, context: ctx)
            }
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
            var seenHashes = Set<String>()
            for entity in entities {
                if let hash = entity.fileHash, let path = entity.fileRelativePath, !seenHashes.contains(hash) {
                    let countReq = SongEntity.fetchRequest()
                    countReq.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO AND NOT (id IN %@)",
                        hash, ids as NSArray)
                    let count = try ctx.count(for: countReq)
                    if count == 0 {
                        filesToMove.append((hash: hash, relativePath: path))
                        seenHashes.insert(hash)
                    }
                }
                entity.softDeleted = true
                entity.deletedAt = now
            }
        }

        for file in filesToMove {
            do {
                let tmpPath = try FileStorageService.shared.moveToPendingDelete(relativePath: file.relativePath)
                movedFiles.append(UndoToken.MovedFile(tempPath: tmpPath, originalRelativePath: file.relativePath))
            } catch {
                ErrorLogger.shared.log(.databaseError(error), context: "softDelete: 文件移动失败 \(file.relativePath)")
                AppLogger.shared.error("softDelete: 文件移动失败 \(file.relativePath): \(error)")
                movedFiles.append(UndoToken.MovedFile(tempPath: "", originalRelativePath: file.relativePath))
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
        let fm = FileManager.default
        for file in token.movedFiles {
            let originalURL = SandboxPathManager.musicFileURL(relativePath: file.originalRelativePath)
            if fm.fileExists(atPath: originalURL.path) {
                continue
            }
            if !file.tempPath.isEmpty {
                do {
                    try FileStorageService.shared.restoreFromPendingDelete(fileName: file.tempPath, originalRelativePath: file.originalRelativePath)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "undoDelete: 文件恢复失败 \(file.originalRelativePath)")
                }
            } else {
                AppLogger.shared.error("undoDelete: 文件既不在待删除目录也不在原始位置: \(file.originalRelativePath)")
            }
        }
    }

    func commitDelete(token: UndoToken) async throws {
        try await stack.performBackground { ctx in
            let songRequest = SongEntity.fetchRequest()
            songRequest.predicate = NSPredicate(format: "id IN %@", token.songIds as NSArray)
            let songs = try ctx.fetch(songRequest)
            for song in songs {
                guard let songId = song.id else {
                    ctx.delete(song)
                    continue
                }
                let psRequest = PlaylistSongEntity.fetchRequest()
                psRequest.predicate = NSPredicate(format: "songId == %@", songId as CVarArg)
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
        try await stack.performBackground { [log] ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                log.debug("toggleFavorite: entity not found id=\(id)")
                return
            }
            entity.isFavorite.toggle()
            entity.favoriteDate = entity.isFavorite ? Date() : nil
        }
    }

    func recordPlay(id: UUID) async throws {
        try await stack.performBackground { [log] ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                log.debug("recordPlay: entity not found id=\(id)")
                return
            }
            entity.playCount += 1
            entity.lastPlayedDate = Date()

            let record = PlayRecordEntity(context: ctx)
            record.id = UUID()
            record.songId = id
            record.playedAt = Date()
        }
    }

    func updateSongInfo(id: UUID, title: String, artist: String, album: String) async throws {
        try await stack.performBackground { [log] ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                log.debug("updateSongInfo: entity not found id=\(id)")
                return
            }
            entity.title = title
            entity.artist = artist
            entity.album = album
        }
    }

    func updateLyrics(songId: UUID, lyricsPath: String?, lyricsSource: LyricsSource?) async throws {
        try await stack.performBackground { [log] ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", songId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                log.debug("updateLyrics: entity not found id=\(songId)")
                return
            }
            entity.lyricsPath = lyricsPath
            entity.lyricsSource = lyricsSource?.rawValue ?? SongMapper.int16Nil
        }
    }

    func cleanupPendingDeletes() async {
        do {
            try await stack.performBackground { ctx in
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
        } catch {
            ErrorLogger.shared.log(.databaseError(error), context: "cleanupPendingDeletes: DB清理失败")
        }
        FileStorageService.shared.cleanupPendingDeleteDirectory()
    }

    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int) async -> PagedResult<Song> {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                var datePredicate: NSPredicate? = nil
                if days > 0 {
                    let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
                    datePredicate = NSPredicate(format: "playedAt >= %@", cutoff as CVarArg)
                }

                let countReq: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "PlayRecordEntity")
                countReq.resultType = .dictionaryResultType
                countReq.propertiesToFetch = ["songId"]
                countReq.returnsDistinctResults = true
                countReq.predicate = datePredicate
                let totalCount = ((try? self.stack.viewContext.fetch(countReq)) ?? []).count

                let startIndex = page * pageSize
                guard startIndex < totalCount else {
                    continuation.resume(returning: PagedResult(items: [], totalCount: totalCount, currentPage: page, hasMore: false))
                    return
                }

                let request = PlayRecordEntity.fetchRequest()
                request.predicate = datePredicate
                request.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
                request.fetchLimit = (startIndex + pageSize) * 10

                let records = (try? self.stack.viewContext.fetch(request)) ?? []
                var seen = Set<UUID>()
                var uniqueIds: [UUID] = []
                for record in records {
                    guard let sid = record.songId, !seen.contains(sid) else { continue }
                    seen.insert(sid)
                    uniqueIds.append(sid)
                    if uniqueIds.count >= startIndex + pageSize { break }
                }

                let endIndex = min(startIndex + pageSize, uniqueIds.count)
                guard startIndex < endIndex else {
                    continuation.resume(returning: PagedResult(items: [], totalCount: totalCount, currentPage: page, hasMore: false))
                    return
                }
                let pageIds = Array(uniqueIds[startIndex..<endIndex])

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

    /// Full-table scan to build artist groups. Acceptable for typical library sizes (< 10k songs).
    /// For very large libraries, consider server-side aggregation or local caching.
    func fetchArtistGroups() async -> [ArtistGroup] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "softDeleted == NO")
                request.propertiesToFetch = ["artist", "album"]
                request.fetchBatchSize = 100
                let results: [SongEntity]
                do {
                    results = try self.stack.viewContext.fetch(request)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchArtistGroups")
                    log.error(error, context: "fetchArtistGroups 查询失败")
                    continuation.resume(returning: [])
                    return
                }

                var groups: [String: (songCount: Int, albums: Set<String>)] = [:]
                for entity in results {
                    let artist = entity.artist ?? SongDefaults.unknownArtist
                    var g = groups[artist] ?? (0, [])
                    g.songCount += 1
                    g.albums.insert(entity.album ?? SongDefaults.unknownAlbum)
                    groups[artist] = g
                }
                let artistGroups = groups.map {
                    ArtistGroup(name: $0.key, songCount: $0.value.songCount, albumCount: $0.value.albums.count)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                continuation.resume(returning: artistGroups)
            }
        }
    }

    func fetchAlbumGroups() async -> [AlbumGroup] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform { [log] in
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "softDeleted == NO")
                request.propertiesToFetch = ["artist", "album", "year", "coverImagePath"]
                request.fetchBatchSize = 100
                let results: [SongEntity]
                do {
                    results = try self.stack.viewContext.fetch(request)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchAlbumGroups")
                    log.error(error, context: "fetchAlbumGroups 查询失败")
                    continuation.resume(returning: [])
                    return
                }

                var groups: [AlbumKey: (year: Int?, count: Int, cover: String?)] = [:]
                for entity in results {
                    let artist = entity.artist ?? SongDefaults.unknownArtist
                    let album = entity.album ?? SongDefaults.unknownAlbum
                    let key = AlbumKey(artist: artist, album: album)
                    var g = groups[key] ?? (entity.year != 0 && entity.year != Int16.min ? Int(entity.year) : nil, 0, entity.coverImagePath)
                    g.count += 1
                    groups[key] = g
                }
                let albumGroups = groups.map {
                    AlbumGroup(name: $0.key.album, artist: $0.key.artist, year: $0.value.year,
                               songCount: $0.value.count, coverImagePath: $0.value.cover)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                continuation.resume(returning: albumGroups)
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

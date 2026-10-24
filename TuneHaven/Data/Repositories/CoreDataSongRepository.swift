import CoreData
import Foundation

final class CoreDataSongRepository: SongRepository, @unchecked Sendable {
    private let stack: CoreDataStack
    private let log = AppLogger.shared

    /// PlayRecord 去重冗余倍数：同一首歌可能有多条播放记录，
    /// 预取该倍数的记录以确保去重后仍有足够唯一歌曲填满当前分页
    private let recentPlayedFetchMultiplier = 10

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    // MARK: - Query Methods

    func fetchAll(sortBy: SongSortOption, ascending: Bool) async throws -> [Song] {
        try await withCheckedThrowingContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "softDeleted == NO")
                request.sortDescriptors = [NSSortDescriptor(key: sortBy.coreDataKey, ascending: ascending)]
                request.fetchBatchSize = 50
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: results.compactMap { SongMapper.toDomain($0) })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetchSong(id: UUID) async -> Song? {
        await performFetch(context: "fetchSong id=\(id)", defaultValue: nil) { request in
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
        } transform: {
            $0.first.flatMap { SongMapper.toDomain($0) }
        }
    }

    func fetchSongs(byIds ids: [UUID]) async -> [Song] {
        guard !ids.isEmpty else { return [] }
        return await performFetch(context: "fetchSongs(byIds:)", defaultValue: []) { request in
            request.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", ids as NSArray)
            request.fetchBatchSize = 50
        } transform: {
            $0.compactMap { SongMapper.toDomain($0) }
        }
    }

    func fetchSongs(byArtist artist: String, sortBy: SongSortOption = .album, ascending: Bool = true) async -> [Song] {
        await performFetch(context: "fetchSongs(byArtist:)", defaultValue: []) { request in
            request.predicate = NSPredicate(format: "artist == %@ AND softDeleted == NO", artist)
            request.sortDescriptors = [NSSortDescriptor(key: sortBy.coreDataKey, ascending: ascending)]
            request.fetchBatchSize = 50
        } transform: {
            $0.compactMap { SongMapper.toDomain($0) }
        }
    }

    func fetchSongs(byAlbum album: String, artist: String, sortBy: SongSortOption = .title, ascending: Bool = true) async -> [Song] {
        await performFetch(context: "fetchSongs(byAlbum:)", defaultValue: []) { request in
            request.predicate = NSPredicate(format: "album == %@ AND artist == %@ AND softDeleted == NO", album, artist)
            request.sortDescriptors = [NSSortDescriptor(key: sortBy.coreDataKey, ascending: ascending)]
            request.fetchBatchSize = 50
        } transform: {
            $0.compactMap { SongMapper.toDomain($0) }
        }
    }

    func fetchByHash(_ hash: String) async -> Song? {
        await performFetch(context: "fetchByHash", defaultValue: nil) { request in
            request.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO", hash)
            request.fetchLimit = 1
        } transform: {
            $0.first.flatMap { SongMapper.toDomain($0) }
        }
    }

    func countReferences(toFileHash hash: String) async -> Int {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                request.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO", hash)
                do {
                    let count = try self.stack.viewContext.count(for: request)
                    continuation.resume(returning: count)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "countReferences")
                    self.log.error(error, context: "countReferences 查询失败")
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    // MARK: - Write Methods

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

        let filesToMove: [[String]] = try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", ids as NSArray)
            let entities = try ctx.fetch(request)
            var seenHashes = Set<String>()
            var result: [[String]] = []
            for entity in entities {
                if let hash = entity.fileHash, let path = entity.fileRelativePath, !seenHashes.contains(hash) {
                    let countReq = SongEntity.fetchRequest()
                    countReq.predicate = NSPredicate(format: "fileHash == %@ AND softDeleted == NO AND NOT (id IN %@)",
                        hash, ids as NSArray)
                    let count = try ctx.count(for: countReq)
                    if count == 0 {
                        result.append([hash, path])
                        seenHashes.insert(hash)
                    }
                }
                entity.softDeleted = true
                entity.deletedAt = now
            }
            return result
        }

        for file in filesToMove {
            let relativePath = file[1]
            do {
                let tmpPath = try FileStorageService.shared.moveToPendingDelete(relativePath: relativePath)
                movedFiles.append(UndoToken.MovedFile(tempPath: tmpPath, originalRelativePath: relativePath))
            } catch {
                ErrorLogger.shared.log(.databaseError(error), context: "softDelete: 文件移动失败 \(relativePath)")
                log.error("softDelete: 文件移动失败 \(relativePath): \(error)")
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
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("toggleFavorite: entity not found id=\(id)")
                return
            }
            entity.isFavorite.toggle()
            entity.favoriteDate = entity.isFavorite ? Date() : nil
        }
    }

    func recordPlay(id: UUID) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("recordPlay: entity not found id=\(id)")
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
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("updateSongInfo: entity not found id=\(id)")
                return
            }
            entity.title = title
            entity.artist = artist
            entity.album = album
        }
    }

    func fetchSongsMissingAudio() async -> [Song] {
        await performFetch(context: "fetchSongsMissingAudio", defaultValue: []) { request in
            request.predicate = NSPredicate(
                format: "softDeleted == NO AND (fileRelativePath BEGINSWITH %@ OR fileRelativePath == %@)",
                Song.missingAudioPathPrefix,
                ""
            )
        } transform: {
            $0.compactMap { SongMapper.toDomain($0) }
        }
    }

    func updateSongMedia(_ song: Song) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", song.id as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                throw AppError.databaseError(NSError(domain: "TuneHaven.Backup", code: 404))
            }
            entity.fileHash = song.fileHash
            entity.fileRelativePath = song.fileRelativePath
            entity.importDate = song.importDate
            entity.softDeleted = false
            entity.deletedAt = nil
            SongMapper.updateEntity(entity, from: song)
        }
    }

    func updateCoverPath(songId: UUID, coverImagePath: String?) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", songId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("updateCoverPath: entity not found id=\(songId)")
                return
            }
            entity.coverImagePath = coverImagePath
        }
    }

    func updateLyrics(songId: UUID, lyricsPath: String?, lyricsSource: LyricsSource?) async throws {
        try await stack.performBackground { ctx in
            let request = SongEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND softDeleted == NO", songId as CVarArg)
            request.fetchLimit = 1
            guard let entity = try ctx.fetch(request).first else {
                self.log.debug("updateLyrics: entity not found id=\(songId)")
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
                        let count: Int
                        do {
                            count = try ctx.count(for: refReq)
                        } catch {
                            ErrorLogger.shared.log(.databaseError(error), context: "cleanupPendingDeletes: 引用计数查询失败 hash=\(hash)")
                            AppLogger.shared.debug("cleanupPendingDeletes: 引用计数查询失败 hash=\(hash) error=\(error)")
                            continue
                        }
                        if count == 0 {
                            let fm = FileManager.default
                            let url = SandboxPathManager.musicFileURL(relativePath: path)
                            do {
                                try fm.removeItem(at: url)
                            } catch {
                                ErrorLogger.shared.log(.databaseError(error), context: "cleanupPendingDeletes: 文件删除失败 \(path)")
                                AppLogger.shared.debug("cleanupPendingDeletes: 文件删除失败 path=\(path) error=\(error)")
                            }
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
                let totalCount: Int
                do {
                    let distinctRecords = try self.stack.viewContext.fetch(countReq)
                    let allSongIds = distinctRecords.compactMap { $0["songId"] as? UUID }
                    let validReq = SongEntity.fetchRequest()
                    validReq.predicate = NSPredicate(format: "id IN %@ AND softDeleted == NO", allSongIds as NSArray)
                    totalCount = try self.stack.viewContext.count(for: validReq)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchRecentlyPlayed: count")
                    self.log.error(error, context: "fetchRecentlyPlayed count 查询失败")
                    continuation.resume(returning: PagedResult(items: [], totalCount: 0, currentPage: page, hasMore: false))
                    return
                }

                let startIndex = page * pageSize
                guard startIndex < totalCount else {
                    continuation.resume(returning: PagedResult(items: [], totalCount: totalCount, currentPage: page, hasMore: false))
                    return
                }

                let request = PlayRecordEntity.fetchRequest()
                request.predicate = datePredicate
                request.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
                request.fetchLimit = (startIndex + pageSize) * self.recentPlayedFetchMultiplier

                let records: [PlayRecordEntity]
                do {
                    records = try self.stack.viewContext.fetch(request)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchRecentlyPlayed: records")
                    self.log.error(error, context: "fetchRecentlyPlayed records 查询失败")
                    continuation.resume(returning: PagedResult(items: [], totalCount: totalCount, currentPage: page, hasMore: false))
                    return
                }
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
                let songEntities: [SongEntity]
                do {
                    songEntities = try self.stack.viewContext.fetch(songReq)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchRecentlyPlayed: songs")
                    self.log.error(error, context: "fetchRecentlyPlayed songs 查询失败")
                    continuation.resume(returning: PagedResult(items: [], totalCount: totalCount, currentPage: page, hasMore: false))
                    return
                }

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

    func fetchArtistGroups() async -> [ArtistGroup] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                do {
                    let countReq: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "SongEntity")
                    countReq.resultType = .dictionaryResultType
                    countReq.predicate = NSPredicate(format: "softDeleted == NO")
                    let countExpr = NSExpressionDescription()
                    countExpr.name = "songCount"
                    countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "id")])
                    countExpr.expressionResultType = .integer64AttributeType
                    countReq.propertiesToFetch = ["artist", countExpr]
                    countReq.propertiesToGroupBy = ["artist"]
                    let songCountResults = try self.stack.viewContext.fetch(countReq)

                    let albumReq: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "SongEntity")
                    albumReq.resultType = .dictionaryResultType
                    albumReq.predicate = NSPredicate(format: "softDeleted == NO")
                    albumReq.propertiesToFetch = ["artist", "album"]
                    albumReq.propertiesToGroupBy = ["artist", "album"]
                    let albumResults = try self.stack.viewContext.fetch(albumReq)
                    var albumCountByArtist: [String: Int] = [:]
                    for dict in albumResults {
                        let artist = (dict["artist"] as? String) ?? SongDefaults.unknownArtist
                        albumCountByArtist[artist, default: 0] += 1
                    }

                    let groups = songCountResults.compactMap { dict -> ArtistGroup? in
                        let artist = (dict["artist"] as? String) ?? SongDefaults.unknownArtist
                        let songCount = (dict["songCount"] as? Int) ?? 0
                        return ArtistGroup(name: artist, songCount: songCount, albumCount: albumCountByArtist[artist] ?? 1)
                    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    continuation.resume(returning: groups)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchArtistGroups")
                    self.log.error(error, context: "fetchArtistGroups 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchAlbumGroups() async -> [AlbumGroup] {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                do {
                    let request: NSFetchRequest<NSDictionary> = NSFetchRequest(entityName: "SongEntity")
                    request.resultType = .dictionaryResultType
                    request.predicate = NSPredicate(format: "softDeleted == NO")
                    let countExpr = NSExpressionDescription()
                    countExpr.name = "songCount"
                    countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "id")])
                    countExpr.expressionResultType = .integer64AttributeType
                    let yearExpr = NSExpressionDescription()
                    yearExpr.name = "maxYear"
                    yearExpr.expression = NSExpression(forFunction: "max:", arguments: [NSExpression(forKeyPath: "year")])
                    yearExpr.expressionResultType = .integer16AttributeType
                    let coverExpr = NSExpressionDescription()
                    coverExpr.name = "cover"
                    coverExpr.expression = NSExpression(forFunction: "max:", arguments: [NSExpression(forKeyPath: "coverImagePath")])
                    coverExpr.expressionResultType = .stringAttributeType
                    request.propertiesToFetch = ["album", "artist", countExpr, yearExpr, coverExpr]
                    request.propertiesToGroupBy = ["album", "artist"]
                    let results = try self.stack.viewContext.fetch(request)

                    let groups = results.compactMap { dict -> AlbumGroup? in
                        let album = (dict["album"] as? String) ?? SongDefaults.unknownAlbum
                        let artist = (dict["artist"] as? String) ?? SongDefaults.unknownArtist
                        let songCount = (dict["songCount"] as? Int) ?? 0
                        let yearVal = dict["maxYear"] as? Int16
                        let year = (yearVal != nil && yearVal! > 0) ? Int(yearVal!) : nil
                        let cover = dict["cover"] as? String
                        return AlbumGroup(name: album, artist: artist, year: year, songCount: songCount, coverImagePath: cover)
                    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    continuation.resume(returning: groups)
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: "fetchAlbumGroups")
                    self.log.error(error, context: "fetchAlbumGroups 查询失败")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func performFetch<T>(
        context: String,
        defaultValue: T,
        configure: @escaping (NSFetchRequest<SongEntity>) -> Void,
        transform: @escaping ([SongEntity]) -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            stack.viewContext.perform {
                let request = SongEntity.fetchRequest()
                configure(request)
                do {
                    let results = try self.stack.viewContext.fetch(request)
                    continuation.resume(returning: transform(results))
                } catch {
                    ErrorLogger.shared.log(.databaseError(error), context: context)
                    self.log.error(error, context: "\(context) 查询失败")
                    continuation.resume(returning: defaultValue)
                }
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

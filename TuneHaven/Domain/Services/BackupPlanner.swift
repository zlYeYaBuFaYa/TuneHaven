import Foundation

enum BackupPlanner {
    static func preview(local: BackupLibrarySnapshot, package: BackupCatalog) -> BackupPreview {
        let conflicts = conflictLists(local: local, package: package)
        return BackupPreview(
            manifest: package.manifest,
            songConflicts: conflicts.songs,
            playlistConflicts: conflicts.playlists
        )
    }

    static func plan(
        local: BackupLibrarySnapshot,
        package: BackupCatalog,
        mode: BackupRestoreMode,
        resolution: BackupConflictResolution,
        now: Date = Date()
    ) -> BackupCommitPlan {
        let preferences = mergedPreferences(local: local.preferences, package: package.preferences)
        if mode == .preferencesOnly {
            var snapshot = local
            snapshot.preferences = preferences
            return BackupCommitPlan(
                snapshot: snapshot,
                copies: [],
                summary: BackupRestoreSummary(preferencesRestored: true)
            )
        }

        let built = mode == .replaceLibrary
            ? buildReplace(local: local, package: package, now: now)
            : buildMerge(local: local, package: package, resolution: resolution, now: now)

        var snapshot = BackupLibrarySnapshot(
            songs: built.songs,
            playlists: built.playlists,
            groups: built.groups,
            preferences: preferences
        )
        snapshot.preferences = preferences
        var summary = built.summary
        summary.preferencesRestored = true
        return BackupCommitPlan(snapshot: snapshot, copies: built.copies, summary: summary)
    }

    // MARK: - Conflicts

    private static func conflictLists(
        local: BackupLibrarySnapshot,
        package: BackupCatalog
    ) -> (songs: [BackupNamedConflict], playlists: [BackupNamedConflict]) {
        var consumedSongs = Set<UUID>()
        var songConflicts: [BackupNamedConflict] = []
        for record in package.songs {
            let candidates = local.songs.map(\.song).filter { !consumedSongs.contains($0.id) }
            guard let match = BackupSongMatcher.bestMatch(
                title: record.title,
                artist: record.artist,
                album: record.album,
                duration: record.duration,
                in: candidates
            ) else { continue }
            consumedSongs.insert(match.id)
            songConflicts.append(BackupNamedConflict(
                id: record.id,
                title: record.title,
                detail: "\(record.artist) · \(record.album)"
            ))
        }

        var consumedPlaylists = Set<UUID>()
        var playlistConflicts: [BackupNamedConflict] = []
        let userPlaylists = local.playlists.filter { !$0.isSystem }
        for record in package.playlists where !BackupSongMatcher.isReservedPlaylistName(record.name) {
            let name = BackupSongMatcher.normalize(record.name)
            guard let match = userPlaylists.first(where: {
                !consumedPlaylists.contains($0.id) && BackupSongMatcher.normalize($0.name) == name
            }) else { continue }
            consumedPlaylists.insert(match.id)
            playlistConflicts.append(BackupNamedConflict(
                id: record.id,
                title: record.name,
                detail: "\(record.songIds.count) 首"
            ))
        }
        return (songConflicts, playlistConflicts)
    }

    // MARK: - Modes

    private struct BuiltLibrary {
        var songs: [BackupLibrarySong]
        var playlists: [BackupLibraryPlaylist]
        var groups: [BackupLibraryGroup]
        var copies: [BackupPlannedCopy]
        var summary: BackupRestoreSummary
    }

    private static func buildReplace(
        local: BackupLibrarySnapshot,
        package: BackupCatalog,
        now: Date
    ) -> BuiltLibrary {
        var summary = BackupRestoreSummary()
        var usedSongIDs = Set<UUID>()
        var idMap: [UUID: UUID] = [:]
        var songs: [BackupLibrarySong] = []
        var copies: [BackupPlannedCopy] = []
        for record in package.songs {
            let id = allocateID(record.id, used: &usedSongIDs)
            idMap[record.id] = id
            let built = makeIncomingSong(record: record, id: id, title: record.title, preserving: nil)
            songs.append(BackupLibrarySong(song: built.song))
            copies.append(contentsOf: built.copies)
            summary.songsAdded += 1
            if built.missingAudio { summary.songsMissingAudio += 1 }
        }
        let groups = groupsIncludingPlaylistNames(
            groupsByReplacing(with: package, now: now),
            package: package,
            now: now
        )
        let playlists = playlistsByReplacing(
            local: local,
            package: package,
            groups: groups,
            idMap: idMap,
            now: now,
            summary: &summary
        )
        return BuiltLibrary(songs: songs, playlists: playlists, groups: groups, copies: copies, summary: summary)
    }

    private static func buildMerge(
        local: BackupLibrarySnapshot,
        package: BackupCatalog,
        resolution: BackupConflictResolution,
        now: Date
    ) -> BuiltLibrary {
        var summary = BackupRestoreSummary()
        var songs = local.songs
        var usedSongIDs = Set(songs.map(\.id))
        var consumed = Set<UUID>()
        var titles = Set(songs.map { BackupSongMatcher.normalize($0.song.title) })
        var idMap: [UUID: UUID] = [:]
        var copies: [BackupPlannedCopy] = []

        for record in package.songs {
            let candidates = songs.map(\.song).filter { !consumed.contains($0.id) }
            let choice = resolution.songChoice(for: record.id)
            if let match = BackupSongMatcher.bestMatch(
                title: record.title,
                artist: record.artist,
                album: record.album,
                duration: record.duration,
                in: candidates
            ) {
                consumed.insert(match.id)
                switch choice {
                case .skip:
                    idMap[record.id] = match.id
                    summary.songsSkipped += 1
                case .replace:
                    let keepAudio = record.audioEntry == nil && !match.isAudioMissing
                    let built = makeIncomingSong(
                        record: record,
                        id: match.id,
                        title: record.title,
                        preserving: keepAudio ? match : nil,
                        playCount: match.playCount,
                        lastPlayed: match.lastPlayedDate,
                        importDate: match.importDate
                    )
                    replaceSong(built.song, in: &songs)
                    copies.append(contentsOf: built.copies)
                    idMap[record.id] = match.id
                    summary.songsReplaced += 1
                    if built.missingAudio { summary.songsMissingAudio += 1 }
                case .saveCopy:
                    let title = BackupSongMatcher.uniqueName(record.title, existing: titles)
                    titles.insert(BackupSongMatcher.normalize(title))
                    let id = allocateID(record.id, used: &usedSongIDs)
                    let built = makeIncomingSong(record: record, id: id, title: title, preserving: nil)
                    songs.append(BackupLibrarySong(song: built.song))
                    copies.append(contentsOf: built.copies)
                    idMap[record.id] = id
                    summary.songsDuplicated += 1
                    if built.missingAudio { summary.songsMissingAudio += 1 }
                }
            } else {
                let id = allocateID(record.id, used: &usedSongIDs)
                let built = makeIncomingSong(record: record, id: id, title: record.title, preserving: nil)
                songs.append(BackupLibrarySong(song: built.song))
                copies.append(contentsOf: built.copies)
                titles.insert(BackupSongMatcher.normalize(record.title))
                idMap[record.id] = id
                summary.songsAdded += 1
                if built.missingAudio { summary.songsMissingAudio += 1 }
            }
        }

        let groups = groupsIncludingPlaylistNames(
            groupsByMerging(local: local, package: package, now: now),
            package: package,
            now: now
        )
        let playlists = playlistsByMerging(
            local: local,
            package: package,
            groups: groups,
            idMap: idMap,
            resolution: resolution,
            now: now,
            summary: &summary
        )
        return BuiltLibrary(songs: songs, playlists: playlists, groups: groups, copies: copies, summary: summary)
    }

    // MARK: - Songs

    private struct IncomingSong {
        var song: Song
        var copies: [BackupPlannedCopy]
        var missingAudio: Bool
    }

    private static func makeIncomingSong(
        record: BackupSongRecord,
        id: UUID,
        title: String,
        preserving localAudio: Song?,
        playCount: Int = 0,
        lastPlayed: Date? = nil,
        importDate: Date? = nil
    ) -> IncomingSong {
        let source = record.lyricsSource.flatMap { Int16(exactly: $0) }.flatMap { LyricsSource(rawValue: $0) }
        if let localAudio {
            var copies: [BackupPlannedCopy] = []
            if let entry = record.coverEntry {
                let key = "backup_\(id.uuidString)_medium.jpg"
                copies.append(BackupPlannedCopy(sourceEntry: entry, destination: .cover(key: key), librarySongId: id))
            }
            if let entry = record.lyricsEntry {
                let relative = "backup-\(id.uuidString).lrc"
                copies.append(BackupPlannedCopy(
                    sourceEntry: entry,
                    destination: .lyrics(relativePath: relative),
                    librarySongId: id,
                    lyricsSource: source ?? .file
                ))
            }
            let song = Song(
                id: id,
                title: title,
                artist: record.artist,
                album: record.album,
                duration: localAudio.duration,
                fileHash: localAudio.fileHash,
                fileRelativePath: localAudio.fileRelativePath,
                coverImagePath: localAudio.coverImagePath,
                lyricsPath: localAudio.lyricsPath,
                lyricsSource: localAudio.lyricsSource,
                metadata: localAudio.metadata,
                importDate: importDate ?? localAudio.importDate,
                fileSize: localAudio.fileSize,
                playCount: playCount,
                isFavorite: record.isFavorite,
                favoriteDate: record.isFavorite ? (record.favoriteDate ?? localAudio.favoriteDate) : nil,
                lastPlayedDate: lastPlayed
            )
            return IncomingSong(song: song, copies: copies, missingAudio: false)
        }

        let hasAudio = record.audioEntry != nil
        let relativePath = hasAudio
            ? "backup-\(id.uuidString).\(audioExtension(record))"
            : Song.missingAudioPath(for: id)
        let hash = record.fileHash.isEmpty ? Song.missingFileHash(for: id) : record.fileHash
        var copies: [BackupPlannedCopy] = []
        if let entry = record.audioEntry {
            copies.append(BackupPlannedCopy(
                sourceEntry: entry,
                destination: .music(relativePath: relativePath),
                librarySongId: id
            ))
        }
        if let entry = record.coverEntry {
            let key = "backup_\(id.uuidString)_medium.jpg"
            copies.append(BackupPlannedCopy(sourceEntry: entry, destination: .cover(key: key), librarySongId: id))
        }
        if let entry = record.lyricsEntry {
            let relative = "backup-\(id.uuidString).lrc"
            copies.append(BackupPlannedCopy(
                sourceEntry: entry,
                destination: .lyrics(relativePath: relative),
                librarySongId: id,
                lyricsSource: source ?? .file
            ))
        }
        let song = Song(
            id: id,
            title: title,
            artist: record.artist,
            album: record.album,
            duration: record.duration,
            fileHash: hash,
            fileRelativePath: relativePath,
            coverImagePath: nil,
            lyricsPath: nil,
            lyricsSource: nil,
            metadata: metadata(from: record),
            importDate: importDate ?? record.importDate,
            fileSize: hasAudio ? record.fileSize : 0,
            playCount: playCount,
            isFavorite: record.isFavorite,
            favoriteDate: record.isFavorite ? record.favoriteDate : nil,
            lastPlayedDate: lastPlayed
        )
        return IncomingSong(song: song, copies: copies, missingAudio: !hasAudio)
    }

    private static func audioExtension(_ record: BackupSongRecord) -> String {
        if let entry = record.audioEntry {
            let ext = (entry as NSString).pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }
        let format = record.format.lowercased()
        return format.isEmpty ? "mp3" : format
    }

    private static func metadata(from record: BackupSongRecord) -> Metadata {
        Metadata(
            format: record.format,
            sampleRate: record.sampleRate,
            bitRate: record.bitRate,
            channels: record.channels,
            encoder: record.encoder,
            trackNumber: record.trackNumber,
            year: record.year,
            genre: record.genre
        )
    }

    private static func replaceSong(_ song: Song, in songs: inout [BackupLibrarySong]) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[index].song = song
    }

    private static func allocateID(_ preferred: UUID, used: inout Set<UUID>) -> UUID {
        if used.insert(preferred).inserted { return preferred }
        var fresh = UUID()
        while !used.insert(fresh).inserted {
            fresh = UUID()
        }
        return fresh
    }

    // MARK: - Groups and playlists

    private static func groupsByReplacing(with package: BackupCatalog, now: Date) -> [BackupLibraryGroup] {
        package.groups
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { record in
                BackupLibraryGroup(
                    id: record.id,
                    name: record.name,
                    sortOrder: record.sortOrder,
                    createdAt: now
                )
            }
    }

    private static func groupsByMerging(
        local: BackupLibrarySnapshot,
        package: BackupCatalog,
        now: Date
    ) -> [BackupLibraryGroup] {
        var groups = local.groups
        var names = Set(groups.map { BackupSongMatcher.normalize($0.name) })
        var used = Set(groups.map(\.id))
        for record in package.groups.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let key = BackupSongMatcher.normalize(record.name)
            if names.contains(key) { continue }
            let id = allocateID(record.id, used: &used)
            groups.append(BackupLibraryGroup(id: id, name: record.name, sortOrder: record.sortOrder, createdAt: now))
            names.insert(key)
        }
        return groups
    }

    private static func groupsIncludingPlaylistNames(
        _ groups: [BackupLibraryGroup],
        package: BackupCatalog,
        now: Date
    ) -> [BackupLibraryGroup] {
        var result = groups
        var names = Set(result.map { BackupSongMatcher.normalize($0.name) })
        for playlist in package.playlists {
            guard let raw = playlist.groupName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let key = BackupSongMatcher.normalize(raw)
            if names.contains(key) { continue }
            result.append(BackupLibraryGroup(id: UUID(), name: raw, sortOrder: result.count, createdAt: now))
            names.insert(key)
        }
        return result
    }

    private static func groupID(named name: String?, in groups: [BackupLibraryGroup]) -> UUID? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = BackupSongMatcher.normalize(trimmed)
        return groups.first { BackupSongMatcher.normalize($0.name) == key }?.id
    }

    private static func playlistsByReplacing(
        local: BackupLibrarySnapshot,
        package: BackupCatalog,
        groups: [BackupLibraryGroup],
        idMap: [UUID: UUID],
        now: Date,
        summary: inout BackupRestoreSummary
    ) -> [BackupLibraryPlaylist] {
        var playlists = local.playlists.filter(\.isSystem)
        var used = Set(playlists.map(\.id))
        var names = Set<String>()
        for record in package.playlists {
            if BackupSongMatcher.isReservedPlaylistName(record.name) {
                summary.playlistsSkipped += 1
                continue
            }
            let id = allocateID(record.id, used: &used)
            let name = BackupSongMatcher.uniqueName(record.name, existing: names)
            names.insert(BackupSongMatcher.normalize(name))
            playlists.append(makePlaylist(
                id: id,
                name: name,
                description: record.description,
                groupId: groupID(named: record.groupName, in: groups),
                sortOrder: record.sortOrder,
                createdAt: now,
                updatedAt: now,
                songIds: mapSongIDs(record.songIds, idMap: idMap)
            ))
            summary.playlistsAdded += 1
        }
        return detachMissingGroups(playlists, groups: groups)
    }

    /// 替换曲库会删掉旧分组。系统歌单若还指着被删分组，改回未分组。
    private static func detachMissingGroups(
        _ playlists: [BackupLibraryPlaylist],
        groups: [BackupLibraryGroup]
    ) -> [BackupLibraryPlaylist] {
        let ids = Set(groups.map(\.id))
        return playlists.map { playlist in
            guard let groupId = playlist.groupId, !ids.contains(groupId) else { return playlist }
            var copy = playlist
            copy.groupId = nil
            return copy
        }
    }

    private static func playlistsByMerging(
        local: BackupLibrarySnapshot,
        package: BackupCatalog,
        groups: [BackupLibraryGroup],
        idMap: [UUID: UUID],
        resolution: BackupConflictResolution,
        now: Date,
        summary: inout BackupRestoreSummary
    ) -> [BackupLibraryPlaylist] {
        let system = local.playlists.filter(\.isSystem)
        var user = local.playlists.filter { !$0.isSystem }
        var consumed = Set<UUID>()
        var names = Set(user.map { BackupSongMatcher.normalize($0.name) })
        var used = Set(local.playlists.map(\.id))

        for record in package.playlists {
            if BackupSongMatcher.isReservedPlaylistName(record.name) {
                summary.playlistsSkipped += 1
                continue
            }
            let key = BackupSongMatcher.normalize(record.name)
            let choice = resolution.playlistChoice(for: record.id)
            if let index = user.firstIndex(where: {
                !consumed.contains($0.id) && BackupSongMatcher.normalize($0.name) == key
            }) {
                let current = user[index]
                consumed.insert(current.id)
                let mapped = mapSongIDs(record.songIds, idMap: idMap)
                switch choice {
                case .replace:
                    user[index].description = record.description
                    user[index].groupId = groupID(named: record.groupName, in: groups)
                    user[index].sortOrder = record.sortOrder
                    user[index].updatedAt = now
                    user[index].songIds = mapped
                    summary.playlistsReplaced += 1
                case .merge:
                    var ids = current.songIds
                    let existing = Set(ids)
                    for songId in mapped where !existing.contains(songId) {
                        ids.append(songId)
                    }
                    user[index].songIds = ids
                    user[index].updatedAt = now
                    if user[index].groupId == nil {
                        user[index].groupId = groupID(named: record.groupName, in: groups)
                    }
                    summary.playlistsMerged += 1
                case .saveCopy:
                    let name = BackupSongMatcher.uniqueName(record.name, existing: names)
                    names.insert(BackupSongMatcher.normalize(name))
                    let id = allocateID(record.id, used: &used)
                    user.append(makePlaylist(
                        id: id,
                        name: name,
                        description: record.description,
                        groupId: groupID(named: record.groupName, in: groups),
                        sortOrder: record.sortOrder,
                        createdAt: now,
                        updatedAt: now,
                        songIds: mapped
                    ))
                    summary.playlistsDuplicated += 1
                }
            } else {
                let name = BackupSongMatcher.uniqueName(record.name, existing: names)
                names.insert(BackupSongMatcher.normalize(name))
                let id = allocateID(record.id, used: &used)
                user.append(makePlaylist(
                    id: id,
                    name: name,
                    description: record.description,
                    groupId: groupID(named: record.groupName, in: groups),
                    sortOrder: record.sortOrder,
                    createdAt: now,
                    updatedAt: now,
                    songIds: mapSongIDs(record.songIds, idMap: idMap)
                ))
                summary.playlistsAdded += 1
            }
        }
        return system + user
    }

    private static func mapSongIDs(_ packageIDs: [UUID], idMap: [UUID: UUID]) -> [UUID] {
        var result: [UUID] = []
        var seen = Set<UUID>()
        for id in packageIDs {
            guard let mapped = idMap[id], seen.insert(mapped).inserted else { continue }
            result.append(mapped)
        }
        return result
    }

    private static func makePlaylist(
        id: UUID,
        name: String,
        description: String?,
        groupId: UUID?,
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date,
        songIds: [UUID]
    ) -> BackupLibraryPlaylist {
        BackupLibraryPlaylist(
            id: id,
            name: name,
            description: description,
            isSystem: false,
            systemTypeRaw: SystemPlaylistType.normal.rawValue,
            groupId: groupId,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            songIds: songIds
        )
    }

    private static func mergedPreferences(
        local: BackupPreferences,
        package: BackupPreferences
    ) -> BackupPreferences {
        var result = local
        if let theme = package.themeStyle?.trimmingCharacters(in: .whitespacesAndNewlines), !theme.isEmpty {
            result.themeStyle = theme
        }
        if let mode = package.playMode, PlayMode(rawValue: mode) != nil {
            result.playMode = mode
        }
        if let speed = package.speedMemoryMode, SpeedMemoryMode(rawValue: speed) != nil {
            result.speedMemoryMode = speed
        }
        if let lyrics = package.lyricsPreferSimplified {
            result.lyricsPreferSimplified = lyrics
        }
        return result
    }
}

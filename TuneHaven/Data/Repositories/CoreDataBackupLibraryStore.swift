import CoreData
import Foundation

/// 用一次 background context save 提交曲库快照。偏好键在保存成功之后才写。
final class CoreDataBackupLibraryStore: BackupLibraryApplying, @unchecked Sendable {
    private let stack: CoreDataStack
    private let defaults: UserDefaults

    init(stack: CoreDataStack = .shared, defaults: UserDefaults = .standard) {
        self.stack = stack
        self.defaults = defaults
    }

    func loadSnapshot() async throws -> BackupLibrarySnapshot {
        let preferences = BackupPreferenceStore.read(from: defaults)
        let body = try await stack.performBackground { context in
            try Self.readBody(in: context)
        }
        return BackupLibrarySnapshot(
            songs: body.songs,
            playlists: body.playlists,
            groups: body.groups,
            preferences: preferences
        )
    }

    func apply(_ snapshot: BackupLibrarySnapshot) async throws {
        let current = try await loadSnapshot()
        if current.libraryBodyEquals(snapshot) {
            BackupPreferenceStore.write(snapshot.preferences, to: defaults)
            return
        }
        try await stack.performBackground { context in
            try Self.writeBody(snapshot, in: context)
        }
        BackupPreferenceStore.write(snapshot.preferences, to: defaults)
    }

    // MARK: - Read

    private struct Body: Sendable {
        var songs: [BackupLibrarySong]
        var playlists: [BackupLibraryPlaylist]
        var groups: [BackupLibraryGroup]
    }

    private static func readBody(in context: NSManagedObjectContext) throws -> Body {
        let songEntities = try context.fetch(SongEntity.fetchRequest())
        let songs = songEntities.compactMap { entity -> BackupLibrarySong? in
            guard entity.softDeleted == false, let song = SongMapper.toDomain(entity) else { return nil }
            return BackupLibrarySong(song: song)
        }

        let linkEntities = try context.fetch(PlaylistSongEntity.fetchRequest())
        var links: [UUID: [(songId: UUID, sortOrder: Int32)]] = [:]
        for link in linkEntities {
            guard let playlistId = link.playlistId, let songId = link.songId else { continue }
            links[playlistId, default: []].append((songId, link.sortOrder))
        }

        let playlistEntities = try context.fetch(PlaylistEntity.fetchRequest())
        let playlists = playlistEntities.compactMap { entity -> BackupLibraryPlaylist? in
            guard let id = entity.id,
                  let name = entity.name,
                  let createdAt = entity.createdAt,
                  let updatedAt = entity.updatedAt else { return nil }
            let ordered = (links[id] ?? []).sorted { $0.sortOrder < $1.sortOrder }.map(\.songId)
            return BackupLibraryPlaylist(
                id: id,
                name: name,
                description: entity.desc_,
                isSystem: entity.isSystem,
                systemTypeRaw: entity.systemType,
                groupId: entity.groupId,
                sortOrder: Int(entity.sortOrder),
                createdAt: createdAt,
                updatedAt: updatedAt,
                songIds: entity.isSystem ? [] : ordered
            )
        }

        let groupEntities = try context.fetch(PlaylistGroupEntity.fetchRequest())
        let groups = groupEntities.compactMap { entity -> BackupLibraryGroup? in
            guard let id = entity.id, let name = entity.name, let createdAt = entity.createdAt else { return nil }
            return BackupLibraryGroup(id: id, name: name, sortOrder: Int(entity.sortOrder), createdAt: createdAt)
        }
        return Body(songs: songs, playlists: playlists, groups: groups)
    }

    // MARK: - Write

    private static func writeBody(_ snapshot: BackupLibrarySnapshot, in context: NSManagedObjectContext) throws {
        try replaceSongs(snapshot.songs.map(\.song), in: context)
        try replaceGroups(snapshot.groups, in: context)
        try replacePlaylists(snapshot.playlists, in: context)
    }

    private static func replaceSongs(_ songs: [Song], in context: NSManagedObjectContext) throws {
        let existing = try context.fetch(SongEntity.fetchRequest())
        var byID: [UUID: SongEntity] = [:]
        for entity in existing {
            if let id = entity.id { byID[id] = entity }
        }
        let keep = Set(songs.map(\.id))
        for entity in existing {
            guard let id = entity.id, !keep.contains(id), entity.softDeleted == false else { continue }
            try deleteLinks(songId: id, playlistId: nil, in: context)
            context.delete(entity)
            byID[id] = nil
        }
        for song in songs {
            if let entity = byID[song.id] {
                entity.fileHash = song.fileHash
                entity.fileRelativePath = song.fileRelativePath
                entity.importDate = song.importDate
                entity.softDeleted = false
                entity.deletedAt = nil
                SongMapper.updateEntity(entity, from: song)
            } else {
                _ = SongMapper.toEntity(song, context: context)
            }
        }
    }

    private static func replaceGroups(_ groups: [BackupLibraryGroup], in context: NSManagedObjectContext) throws {
        let existing = try context.fetch(PlaylistGroupEntity.fetchRequest())
        var byID: [UUID: PlaylistGroupEntity] = [:]
        for entity in existing {
            if let id = entity.id { byID[id] = entity }
        }
        let keep = Set(groups.map(\.id))
        for entity in existing {
            guard let id = entity.id, !keep.contains(id) else { continue }
            context.delete(entity)
        }
        for group in groups {
            if let entity = byID[group.id] {
                entity.name = group.name
                entity.sortOrder = Int32(clamping: group.sortOrder)
            } else {
                let entity = PlaylistGroupEntity(context: context)
                entity.id = group.id
                entity.name = group.name
                entity.sortOrder = Int32(clamping: group.sortOrder)
                entity.createdAt = group.createdAt
            }
        }
    }

    private static func replacePlaylists(_ playlists: [BackupLibraryPlaylist], in context: NSManagedObjectContext) throws {
        let existing = try context.fetch(PlaylistEntity.fetchRequest())
        var byID: [UUID: PlaylistEntity] = [:]
        for entity in existing {
            if let id = entity.id { byID[id] = entity }
        }
        let keep = Set(playlists.map(\.id))
        for entity in existing {
            guard let id = entity.id, !entity.isSystem, !keep.contains(id) else { continue }
            try deleteLinks(songId: nil, playlistId: id, in: context)
            context.delete(entity)
        }
        for playlist in playlists {
            let entity: PlaylistEntity
            if let current = byID[playlist.id] {
                entity = current
                entity.name = playlist.name
                entity.desc_ = playlist.description
                entity.isSystem = playlist.isSystem
                entity.systemType = playlist.systemTypeRaw
                entity.groupId = playlist.groupId
                entity.sortOrder = Int32(clamping: playlist.sortOrder)
                entity.updatedAt = playlist.updatedAt
            } else {
                entity = PlaylistEntity(context: context)
                entity.id = playlist.id
                entity.name = playlist.name
                entity.desc_ = playlist.description
                entity.isSystem = playlist.isSystem
                entity.systemType = playlist.systemTypeRaw
                entity.groupId = playlist.groupId
                entity.sortOrder = Int32(clamping: playlist.sortOrder)
                entity.createdAt = playlist.createdAt
                entity.updatedAt = playlist.updatedAt
            }
            guard !playlist.isSystem else { continue }
            try deleteLinks(songId: nil, playlistId: playlist.id, in: context)
            for (offset, songId) in playlist.songIds.enumerated() {
                let link = PlaylistSongEntity(context: context)
                link.playlistId = playlist.id
                link.songId = songId
                link.sortOrder = Int32(clamping: offset)
                link.addedAt = playlist.updatedAt
            }
        }
    }

    private static func deleteLinks(songId: UUID?, playlistId: UUID?, in context: NSManagedObjectContext) throws {
        let request = PlaylistSongEntity.fetchRequest()
        if let songId, let playlistId {
            request.predicate = NSPredicate(
                format: "songId == %@ AND playlistId == %@",
                songId as CVarArg,
                playlistId as CVarArg
            )
        } else if let songId {
            request.predicate = NSPredicate(format: "songId == %@", songId as CVarArg)
        } else if let playlistId {
            request.predicate = NSPredicate(format: "playlistId == %@", playlistId as CVarArg)
        } else {
            return
        }
        for link in try context.fetch(request) {
            context.delete(link)
        }
    }
}

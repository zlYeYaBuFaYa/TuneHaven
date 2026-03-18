import CoreData
import Foundation

enum PlaylistMapper {
    static func toDomain(_ entity: PlaylistEntity) -> Playlist? {
        guard let id = entity.id,
              let name = entity.name,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt else { return nil }

        let systemType = SystemPlaylistType(rawValue: entity.systemType) ?? .normal
        let songCount = computeSongCount(entity: entity, id: id, systemType: systemType)
        let coverPath = entity.customCoverPath ?? entity.autoCoverPath

        return Playlist(
            id: id,
            name: name,
            description: entity.desc_,
            coverImagePath: coverPath,
            autoCoverHash: entity.autoCoverHash,
            isSystem: entity.isSystem,
            systemType: systemType,
            songCount: songCount,
            groupId: entity.groupId,
            sortOrder: Int(entity.sortOrder),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func computeSongCount(entity: PlaylistEntity, id: UUID, systemType: SystemPlaylistType) -> Int {
        guard let ctx = entity.managedObjectContext else {
            return (entity.songs?.allObjects as? [PlaylistSongEntity])?.count ?? 0
        }

        if entity.isSystem {
            switch systemType {
            case .favorites:
                let req = SongEntity.fetchRequest() as NSFetchRequest<SongEntity>
                req.predicate = NSPredicate(format: "isFavorite == YES AND softDeleted == NO")
                return (try? ctx.fetch(req))?.count ?? 0
            case .recentlyPlayed:
                let req = SongEntity.fetchRequest() as NSFetchRequest<SongEntity>
                req.predicate = NSPredicate(format: "lastPlayedDate != nil AND softDeleted == NO")
                return (try? ctx.fetch(req))?.count ?? 0
            default:
                return 0
            }
        } else {
            let req = PlaylistSongEntity.fetchRequest() as NSFetchRequest<PlaylistSongEntity>
            req.predicate = NSPredicate(format: "playlistId == %@", id as CVarArg)
            req.includesSubentities = false
            req.includesPropertyValues = false
            return (try? ctx.fetch(req))?.count ?? 0
        }
    }

    static func toEntity(_ playlist: Playlist, context: NSManagedObjectContext) -> PlaylistEntity {
        let entity = PlaylistEntity(context: context)
        entity.id = playlist.id
        entity.name = playlist.name
        entity.desc_ = playlist.description
        entity.isSystem = playlist.isSystem
        entity.systemType = playlist.systemType.rawValue
        entity.groupId = playlist.groupId
        entity.sortOrder = Int32(playlist.sortOrder)
        entity.createdAt = playlist.createdAt
        entity.updatedAt = playlist.updatedAt
        entity.autoCoverHash = playlist.autoCoverHash
        if playlist.autoCoverHash != nil {
            entity.autoCoverPath = playlist.coverImagePath
        } else {
            entity.customCoverPath = playlist.coverImagePath
        }
        return entity
    }
}

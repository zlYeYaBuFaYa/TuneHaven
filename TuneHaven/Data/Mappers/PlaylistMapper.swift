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
                return (try? ctx.count(for: req)) ?? 0
            case .recentlyPlayed:
                let req = SongEntity.fetchRequest() as NSFetchRequest<SongEntity>
                req.predicate = NSPredicate(format: "lastPlayedDate != nil AND softDeleted == NO")
                return (try? ctx.count(for: req)) ?? 0
            default:
                return 0
            }
        } else {
            let req = PlaylistSongEntity.fetchRequest() as NSFetchRequest<PlaylistSongEntity>
            req.predicate = NSPredicate(format: "playlistId == %@", id as CVarArg)
            req.includesSubentities = false
            req.includesPropertyValues = false
            return (try? ctx.count(for: req)) ?? 0
        }
    }

}

import CoreData
import Foundation

enum PlaylistMapper {
    static func toDomain(_ entity: PlaylistEntity) -> Playlist? {
        guard let id = entity.id,
              let name = entity.name,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt else { return nil }

        let songCount = (entity.songs?.allObjects as? [PlaylistSongEntity])?.count ?? 0
        let coverPath = entity.customCoverPath ?? entity.autoCoverPath

        return Playlist(
            id: id,
            name: name,
            description: entity.desc_,
            coverImagePath: coverPath,
            autoCoverHash: entity.autoCoverHash,
            isSystem: entity.isSystem,
            systemType: SystemPlaylistType(rawValue: entity.systemType) ?? .normal,
            songCount: songCount,
            groupId: entity.groupId,
            sortOrder: Int(entity.sortOrder),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
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
        return entity
    }
}

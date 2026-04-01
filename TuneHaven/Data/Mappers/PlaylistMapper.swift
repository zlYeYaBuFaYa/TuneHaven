import CoreData
import Foundation

enum PlaylistMapper {
    static func toDomain(_ entity: PlaylistEntity, songCount: Int) -> Playlist? {
        guard let id = entity.id,
              let name = entity.name,
              let createdAt = entity.createdAt,
              let updatedAt = entity.updatedAt else { return nil }

        let systemType = SystemPlaylistType(rawValue: entity.systemType) ?? .normal
        let coverPath = entity.customCoverPath ?? entity.autoCoverPath

        return Playlist(
            id: id,
            name: name,
            // desc_ 使用下划线后缀避免与 NSObject.description 冲突
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

    static func toEntity(from playlist: Playlist, context: NSManagedObjectContext) -> PlaylistEntity {
        let entity = PlaylistEntity(context: context)
        entity.id = playlist.id
        entity.name = playlist.name
        entity.desc_ = playlist.description
        entity.isSystem = playlist.isSystem
        entity.systemType = playlist.systemType.rawValue
        entity.sortOrder = Int32(playlist.sortOrder)
        entity.groupId = playlist.groupId
        entity.createdAt = playlist.createdAt
        entity.updatedAt = playlist.updatedAt
        return entity
    }

    static func updateEntity(_ entity: PlaylistEntity, from playlist: Playlist) {
        entity.name = playlist.name
        entity.desc_ = playlist.description
        entity.sortOrder = Int32(playlist.sortOrder)
        entity.groupId = playlist.groupId
        entity.updatedAt = playlist.updatedAt
    }
}

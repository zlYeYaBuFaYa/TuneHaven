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
}

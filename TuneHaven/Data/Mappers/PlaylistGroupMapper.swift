import CoreData
import Foundation

enum PlaylistGroupMapper {
    static func toDomain(_ entity: PlaylistGroupEntity) -> PlaylistGroup? {
        guard let id = entity.id,
              let name = entity.name,
              let createdAt = entity.createdAt else { return nil }
        return PlaylistGroup(id: id, name: name, createdAt: createdAt, sortOrder: Int(entity.sortOrder))
    }

    static func toEntity(from group: PlaylistGroup, context: NSManagedObjectContext) -> PlaylistGroupEntity {
        let entity = PlaylistGroupEntity(context: context)
        entity.id = group.id
        entity.name = group.name
        entity.sortOrder = Int32(group.sortOrder)
        entity.createdAt = group.createdAt
        return entity
    }
}

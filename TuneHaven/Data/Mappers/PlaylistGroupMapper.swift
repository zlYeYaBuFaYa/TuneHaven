import CoreData
import Foundation

enum PlaylistGroupMapper {
    static func toDomain(_ entity: PlaylistGroupEntity) -> PlaylistGroup? {
        guard let id = entity.id,
              let name = entity.name,
              let createdAt = entity.createdAt else { return nil }
        return PlaylistGroup(id: id, name: name, createdAt: createdAt, sortOrder: Int(entity.sortOrder))
    }
}

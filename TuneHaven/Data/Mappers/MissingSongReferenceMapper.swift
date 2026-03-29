import CoreData
import Foundation

enum MissingSongReferenceMapper {
    static func toDomain(_ entity: MissingSongReferenceEntity) -> MissingSongReference? {
        guard let id = entity.id,
              let title = entity.title,
              let artist = entity.artist,
              let album = entity.album,
              let playlistId = entity.playlistId else { return nil }

        return MissingSongReference(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: entity.duration,
            playlistId: playlistId
        )
    }
}

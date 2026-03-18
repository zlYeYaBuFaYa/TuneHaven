import CoreData
import Foundation

enum SongMapper {
    static func toEntity(_ song: Song, context: NSManagedObjectContext) -> SongEntity {
        let entity = SongEntity(context: context)
        entity.id = song.id
        entity.title = song.title
        entity.artist = song.artist
        entity.album = song.album
        entity.duration = song.duration
        entity.fileHash = song.fileHash
        entity.fileRelativePath = song.fileRelativePath
        entity.coverImagePath = song.coverImagePath
        entity.lyricsPath = song.lyricsPath
        entity.lyricsSource = song.lyricsSource?.rawValue ?? 0
        entity.format = song.metadata.format
        entity.sampleRate = Int32(song.metadata.sampleRate ?? 0)
        entity.bitRate = Int32(song.metadata.bitRate ?? 0)
        entity.channels = Int16(song.metadata.channels ?? 0)
        entity.encoder = song.metadata.encoder
        entity.trackNumber = Int16(song.metadata.trackNumber ?? 0)
        entity.year = Int16(song.metadata.year ?? 0)
        entity.genre = song.metadata.genre
        entity.importDate = song.importDate
        entity.fileSize = song.fileSize
        entity.playCount = Int32(song.playCount)
        entity.isFavorite = song.isFavorite
        entity.favoriteDate = song.favoriteDate
        entity.lastPlayedDate = song.lastPlayedDate
        entity.softDeleted = false
        return entity
    }

    static func toDomain(_ entity: SongEntity) -> Song? {
        guard let id = entity.id,
              let title = entity.title,
              let artist = entity.artist,
              let album = entity.album,
              let fileHash = entity.fileHash,
              let fileRelativePath = entity.fileRelativePath,
              let format = entity.format,
              let importDate = entity.importDate else { return nil }

        let metadata = Metadata(
            format: format,
            sampleRate: entity.sampleRate != 0 ? Int(entity.sampleRate) : nil,
            bitRate: entity.bitRate != 0 ? Int(entity.bitRate) : nil,
            channels: entity.channels != 0 ? Int(entity.channels) : nil,
            encoder: entity.encoder,
            trackNumber: entity.trackNumber != 0 ? Int(entity.trackNumber) : nil,
            year: entity.year != 0 ? Int(entity.year) : nil,
            genre: entity.genre
        )

        return Song(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: entity.duration,
            fileHash: fileHash,
            fileRelativePath: fileRelativePath,
            coverImagePath: entity.coverImagePath,
            lyricsPath: entity.lyricsPath,
            lyricsSource: entity.lyricsSource != 0 ? LyricsSource(rawValue: entity.lyricsSource) : nil,
            metadata: metadata,
            importDate: importDate,
            fileSize: entity.fileSize,
            playCount: Int(entity.playCount),
            isFavorite: entity.isFavorite,
            favoriteDate: entity.favoriteDate,
            lastPlayedDate: entity.lastPlayedDate
        )
    }
}

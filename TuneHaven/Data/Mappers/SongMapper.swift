import CoreData
import Foundation

enum SongMapper {
    /// Creates a new SongEntity for initial import; sets softDeleted = false.
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
        entity.lyricsSource = song.lyricsSource?.rawValue ?? Int16.min
        entity.format = song.metadata.format
        entity.sampleRate = Int32(song.metadata.sampleRate ?? 0)
        entity.bitRate = Int32(song.metadata.bitRate ?? 0)
        entity.channels = Int16(song.metadata.channels ?? 0)
        entity.encoder = song.metadata.encoder
        entity.trackNumber = song.metadata.trackNumber.map { Int16($0) } ?? Int16.min
        entity.year = song.metadata.year.map { Int16($0) } ?? Int16.min
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
            trackNumber: Self.isValidOptionalInt16(entity.trackNumber) ? Int(entity.trackNumber) : nil,
            year: Self.isValidOptionalInt16(entity.year) ? Int(entity.year) : nil,
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
            lyricsSource: Self.isValidLyricsSource(entity.lyricsSource) ? LyricsSource(rawValue: entity.lyricsSource) : nil,
            metadata: metadata,
            importDate: importDate,
            fileSize: entity.fileSize,
            playCount: Int(entity.playCount),
            isFavorite: entity.isFavorite,
            favoriteDate: entity.favoriteDate,
            lastPlayedDate: entity.lastPlayedDate
        )
    }

    /// Handles both old sentinel (`0`) and new sentinel (`Int16.min`) for trackNumber/year.
    private static func isValidOptionalInt16(_ value: Int16) -> Bool {
        value != 0 && value != Int16.min
    }

    /// Handles both old sentinel (`-1`) and new sentinel (`Int16.min`) for lyricsSource.
    private static func isValidLyricsSource(_ value: Int16) -> Bool {
        value != -1 && value != Int16.min
    }
}

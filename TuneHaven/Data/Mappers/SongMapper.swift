import CoreData
import Foundation

enum SongMapper {
    static let int16Nil: Int16 = Int16.min

    static func toEntity(_ song: Song, context: NSManagedObjectContext) -> SongEntity {
        let entity = SongEntity(context: context)
        entity.id = song.id
        entity.fileRelativePath = song.fileRelativePath
        entity.fileHash = song.fileHash
        entity.importDate = song.importDate
        entity.softDeleted = false
        applyCommonFields(entity: entity, from: song)
        return entity
    }

    static func updateEntity(_ entity: SongEntity, from song: Song) {
        applyCommonFields(entity: entity, from: song)
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
            trackNumber: Self.isValidTrackNumber(entity.trackNumber) ? Int(entity.trackNumber) : nil,
            year: Self.isValidYear(entity.year) ? Int(entity.year) : nil,
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

    private static func isValidTrackNumber(_ value: Int16) -> Bool {
        value != int16Nil && value >= 0
    }

    private static func isValidYear(_ value: Int16) -> Bool {
        value > 0
    }

    // MARK: - Private

    private static func applyCommonFields(entity: SongEntity, from song: Song) {
        entity.title = song.title
        entity.artist = song.artist
        entity.album = song.album
        entity.duration = song.duration
        entity.coverImagePath = song.coverImagePath
        entity.lyricsPath = song.lyricsPath
        entity.lyricsSource = song.lyricsSource?.rawValue ?? int16Nil
        entity.format = song.metadata.format
        entity.sampleRate = Int32(song.metadata.sampleRate ?? 0)
        entity.bitRate = Int32(song.metadata.bitRate ?? 0)
        entity.channels = Int16(song.metadata.channels ?? 0)
        entity.encoder = song.metadata.encoder
        entity.trackNumber = song.metadata.trackNumber.map { Int16($0) } ?? int16Nil
        entity.year = song.metadata.year.map { Int16($0) } ?? int16Nil
        entity.genre = song.metadata.genre
        entity.fileSize = song.fileSize
        entity.playCount = Int32(song.playCount)
        entity.isFavorite = song.isFavorite
        entity.favoriteDate = song.favoriteDate
        entity.lastPlayedDate = song.lastPlayedDate
    }

    private static func isValidLyricsSource(_ value: Int16) -> Bool {
        value != -1 && value != int16Nil
    }
}

import CoreData
import Foundation

enum SongMapper {
    static let int16Nil: Int16 = Int16.min

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
        entity.lyricsSource = song.lyricsSource?.rawValue ?? Self.int16Nil
        entity.format = song.metadata.format
        // nil → 0: CoreData 不支持 Optional<Int>，0 作为"未知"哨兵值，toDomain 时还原为 nil
        entity.sampleRate = Int32(song.metadata.sampleRate ?? 0)
        entity.bitRate = Int32(song.metadata.bitRate ?? 0)
        entity.channels = Int16(song.metadata.channels ?? 0)
        entity.encoder = song.metadata.encoder
        // nil → Int16.min: 使用 int16Nil 哨兵区分"无值"与合法值 0
        entity.trackNumber = song.metadata.trackNumber.map { Int16($0) } ?? Self.int16Nil
        entity.year = song.metadata.year.map { Int16($0) } ?? Self.int16Nil
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

    static func updateEntity(_ entity: SongEntity, from song: Song) {
        entity.title = song.title
        entity.artist = song.artist
        entity.album = song.album
        entity.duration = song.duration
        entity.coverImagePath = song.coverImagePath
        entity.lyricsPath = song.lyricsPath
        entity.lyricsSource = song.lyricsSource?.rawValue ?? Self.int16Nil
        entity.format = song.metadata.format
        // nil → 0: CoreData 不支持 Optional<Int>，0 作为"未知"哨兵值，toDomain 时还原为 nil
        entity.sampleRate = Int32(song.metadata.sampleRate ?? 0)
        entity.bitRate = Int32(song.metadata.bitRate ?? 0)
        entity.channels = Int16(song.metadata.channels ?? 0)
        entity.encoder = song.metadata.encoder
        // nil → Int16.min: 使用 int16Nil 哨兵区分"无值"与合法值 0
        entity.trackNumber = song.metadata.trackNumber.map { Int16($0) } ?? Self.int16Nil
        entity.year = song.metadata.year.map { Int16($0) } ?? Self.int16Nil
        entity.genre = song.metadata.genre
        entity.fileSize = song.fileSize
        entity.softDeleted = false
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

        // 0 表示未知/未解析，映射为 nil
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

    static func isValidTrackNumber(_ value: Int16) -> Bool {
        value != int16Nil && value >= 0
    }

    static func isValidYear(_ value: Int16) -> Bool {
        value > 0
    }

    private static func isValidLyricsSource(_ value: Int16) -> Bool {
        value != -1 && value != int16Nil
    }
}

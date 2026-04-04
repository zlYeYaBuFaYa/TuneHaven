import Foundation

enum SongDefaults {
    static let unknownArtist = NSLocalizedString("unknown_artist", value: "未知艺术家", comment: "Fallback artist name when metadata is missing")
    static let unknownAlbum = NSLocalizedString("unknown_album", value: "未知专辑", comment: "Fallback album name when metadata is missing")
}

struct Song: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    let duration: TimeInterval
    let fileHash: String
    let fileRelativePath: String
    var coverImagePath: String?
    var lyricsPath: String?
    var lyricsSource: LyricsSource?
    let metadata: Metadata
    let importDate: Date
    let fileSize: Int64
    var playCount: Int
    var isFavorite: Bool
    var favoriteDate: Date?
    var lastPlayedDate: Date?

    /// 判断歌曲是否为无损格式。
    /// 优先使用 AudioFormat 精确匹配，m4a 容器需额外检查编码器或比特率。
    var isLossless: Bool {
        let fmt = metadata.format.lowercased()
        if let audioFormat = AudioFormat(rawValue: fmt), audioFormat.isLossless {
            return true
        }
        if fmt == "aif" { return true }
        guard fmt == "m4a" else { return false }
        if let encoder = metadata.encoder?.lowercased() {
            return encoder.contains("alac") || encoder.contains("apple lossless")
        }
        if let bitRate = metadata.bitRate, bitRate > 600 {
            return true
        }
        return false
    }
}

enum LyricsSource: Int16, Codable {
    case embedded = 0
    case file = 1
    case manual = 2
}

struct Metadata: Hashable, Sendable {
    let format: String
    let sampleRate: Int?
    let bitRate: Int?
    let channels: Int?
    let encoder: String?
    let trackNumber: Int?
    let year: Int?
    let genre: String?
}

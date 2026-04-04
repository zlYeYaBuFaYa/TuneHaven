import Foundation

// TODO: 国际化 — 当前仅支持中文，后续改为 NSLocalizedString
enum SongDefaults {
    static let unknownArtist = "未知艺术家"
    static let unknownAlbum = "未知专辑"
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

    /// 判断歌曲是否为无损格式
    var isLossless: Bool {
        let fmt = metadata.format.lowercased()
        switch fmt {
        case "flac", "wav", "aiff", "aif", "caf":
            return true
        case "m4a", "alac":
            if let encoder = metadata.encoder?.lowercased() {
                return encoder.contains("alac") || encoder.contains("apple lossless")
            }
            if let bitRate = metadata.bitRate, bitRate > 600 {
                return true
            }
            return fmt == "alac"
        default:
            return false
        }
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

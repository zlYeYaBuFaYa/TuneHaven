import Foundation

struct Song: Identifiable, Hashable {
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

    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// "3:45" 格式的时长字符串
    func formatDuration() -> String {
        let total = Int(duration)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// 文件大小友好展示
    func formatFileSize() -> String {
        let mb = Double(fileSize) / 1024 / 1024
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%d KB", fileSize / 1024)
    }
}

enum LyricsSource: Int16, Codable {
    case embedded = 0
    case file = 1
    case manual = 2
}

struct Metadata: Hashable {
    let format: String
    let sampleRate: Int?
    let bitRate: Int?
    let channels: Int?
    let encoder: String?
    let trackNumber: Int?
    let year: Int?
    let genre: String?
}

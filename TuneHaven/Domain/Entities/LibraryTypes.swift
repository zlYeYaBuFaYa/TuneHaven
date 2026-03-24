import Foundation

struct ArtistGroup: Identifiable, Hashable {
    let name: String
    let songCount: Int
    let albumCount: Int
    /// id 使用艺术家名称，假定名称在数据库中唯一；如果不同来源存在同名艺术家，需要额外区分键。
    var id: String { name }
}

struct AlbumKey: Hashable {
    let artist: String
    let album: String
}

struct AlbumGroup: Identifiable, Hashable {
    let name: String
    let artist: String
    let year: Int?
    let songCount: Int
    let coverImagePath: String?
    /// Uses null separator U+0000 to avoid collisions when artist or album names contain "/"
    var id: String { "\(artist)\0\(name)" }
}

struct ArtistDetail {
    let name: String
    let albums: [AlbumGroup]
    let allSongs: [Song]
}

struct AlbumDetail {
    let name: String
    let artist: String
    let year: Int?
    let songs: [Song]
    let coverImagePath: String?
}

enum SongSortOption: Int, CaseIterable {
    case title = 0
    case fileSize
    case importDate
    case artist
    case album
    case duration
}

enum AudioFormat: String, CaseIterable {
    case all = "all"
    case mp3 = "mp3"
    case m4a = "m4a"
    case aac = "aac"
    case alac = "alac"
    case wav = "wav"
    case flac = "flac"
    case aiff = "aiff"
    case caf = "caf"

    var isLossless: Bool {
        switch self {
        case .alac, .wav, .flac, .aiff, .caf: return true
        default: return false
        }
    }
}

enum LibraryTab: String, CaseIterable {
    case all = "all"
    case artist = "artist"
    case album = "album"
}

enum PlayMode: Int, CaseIterable {
    case sequential = 0
    case repeatOne
    case repeatAll
    case shuffle
}

enum SpeedMemoryMode: Int, CaseIterable {
    case global = 0
    case perSong = 1
}

enum RecentPlayRange: Int, CaseIterable, Identifiable {
    case three  = 3
    case seven  = 7
    case fourteen = 14
    case thirty = 30
    case all    = 0

    var id: Int { rawValue }
    var days: Int { rawValue }

    var displayName: String {
        switch self {
        case .three:    return "最近 3 天"
        case .seven:    return "最近 7 天"
        case .fourteen: return "最近 14 天"
        case .thirty:   return "最近 30 天"
        case .all:      return "全部历史"
        }
    }

    init?(days: Int) {
        self.init(rawValue: days)
    }
}

enum PlayContext {
    case allSongs(sortBy: SongSortOption)
    case album(name: String, artist: String)
    case artist(name: String)
    case playlist(id: UUID)
    case recentlyPlayed(days: Int)
    case queue
}

enum ImportFileStatus: Equatable {
    case success
    case successIncompleteMetadata
    case skippedDuplicate
    case skippedUnsupportedFormat
    case skippedOversize
    case failed
}

struct ImportOverrides {
    let title: String?
    let artist: String?
    let album: String?
    let coverData: Data?

    init(title: String? = nil, artist: String? = nil, album: String? = nil, coverData: Data? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.coverData = coverData
    }
}

struct ImportProgress {
    let currentFileName: String
    let completedCount: Int
    let totalCount: Int
    let percentage: Double
    let estimatedRemainingSeconds: TimeInterval?
}

struct ImportResult {
    let successCount: Int
    let skippedDuplicateCount: Int
    let skippedFormatCount: Int
    let failedCount: Int
    let incompleteMetadataCount: Int
    let skippedOversizeCount: Int
    let details: [SingleImportResult]
}

struct SingleImportResult {
    let fileName: String
    let status: ImportFileStatus
    let song: Song?
    let errorMessage: String?
}

struct SearchResult {
    /// 按当前 tab 过滤后的歌曲列表
    let songs: [Song]
    let artists: [ArtistGroup]
    let albums: [AlbumGroup]
    /// 所有匹配关键词的歌曲总数（未经 tab 过滤），用于搜索结果标题展示。
    /// 注意：在 .all tab 下 == songs.count；在 .artist/.album tab 下 >= songs.count。
    let totalMatchCount: Int
    let totalArtistCount: Int
    let totalAlbumCount: Int

    static let empty = SearchResult(songs: [], artists: [], albums: [],
                                    totalMatchCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
}

struct SearchHistoryItem: Identifiable {
    let id: UUID
    let keyword: String
    let searchedAt: Date
}

struct LyricsData {
    let source: LyricsSource
    let lines: [LyricsLine]
    let rawText: String
}

struct LyricsLine: Identifiable {
    /// 使用 UUID 作为 SwiftUI List/ForEach 的稳定标识符。
    /// 每次解析 LRC 都会生成新实例，UUID 确保 diff 正确触发视图更新。
    let id: UUID
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
    }
}

class UndoToken {
    struct MovedFile {
        let tempPath: String
        let originalRelativePath: String
    }
    let songIds: [UUID]
    let movedFiles: [MovedFile]
    let expiresAt: Date
    var timerKey: UUID?

    init(songIds: [UUID], movedFiles: [MovedFile], expiresAt: Date) {
        self.songIds = songIds
        self.movedFiles = movedFiles
        self.expiresAt = expiresAt
    }
}

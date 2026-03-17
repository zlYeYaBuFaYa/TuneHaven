import Foundation

struct ArtistGroup: Identifiable, Hashable {
    let name: String
    let songCount: Int
    let albumCount: Int
    var id: String { name }
}

struct AlbumGroup: Identifiable, Hashable {
    let name: String
    let artist: String
    let year: Int?
    let songCount: Int
    let coverImagePath: String?
    var id: String { "\(artist)/\(name)" }
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

    var displayName: String {
        switch self {
        case .title: return "文件名"
        case .fileSize: return "文件大小"
        case .importDate: return "添加时间"
        case .artist: return "艺术家"
        case .album: return "专辑"
        case .duration: return "时长"
        }
    }
}

enum AudioFormat: String, CaseIterable {
    case all = "all"
    case mp3 = "mp3"
    case m4a = "m4a"
    case aac = "aac"
    case alac = "alac"
    case wav = "wav"
    case flac = "flac"

    var displayName: String {
        switch self {
        case .all: return "全部格式"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .aac: return "AAC"
        case .alac: return "ALAC（无损）"
        case .wav: return "WAV"
        case .flac: return "FLAC（暂不支持播放）"
        }
    }
}

enum LibraryTab: String, CaseIterable {
    case all = "all"
    case artist = "artist"
    case album = "album"

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .artist: return "艺术家"
        case .album: return "专辑"
        }
    }
}

enum PlayMode: Int, CaseIterable {
    case sequential = 0
    case repeatOne
    case repeatAll
    case shuffle

    var displayName: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单曲循环"
        case .repeatAll: return "列表循环"
        case .shuffle: return "随机播放"
        }
    }

    var iconName: String {
        switch self {
        case .sequential: return "arrow.right"
        case .repeatOne: return "repeat.1"
        case .repeatAll: return "repeat"
        case .shuffle: return "shuffle"
        }
    }
}

enum PlayContext {
    case allSongs(sortBy: SongSortOption)
    case album(name: String, artist: String)
    case artist(name: String)
    case playlist(id: UUID)
    case queue
}

enum ImportFileStatus {
    case success
    case successIncompleteMetadata
    case skippedDuplicate
    case skippedUnsupportedFormat
    case skippedOversize
    case failed
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
    let songs: [Song]
    let artists: [ArtistGroup]
    let albums: [AlbumGroup]
    let totalSongCount: Int
    let totalArtistCount: Int
    let totalAlbumCount: Int
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
    let id: UUID
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
    }
}

struct UndoToken {
    let songIds: [UUID]
    let tempFilePaths: [String]
    let expiresAt: Date
}

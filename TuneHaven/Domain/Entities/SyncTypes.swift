import Foundation

// MARK: - 导出数据模型

struct SongExportData: Codable, Hashable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let format: String
    let sampleRate: Int?
    let bitRate: Int?
    let channels: Int?
    let trackNumber: Int?
    let year: Int?
    let genre: String?
    let audioFileName: String
    let coverFileName: String?
    let lyricsFileName: String?
}

extension SongExportData {
    init(song: Song, audioFileName: String, coverFileName: String?, lyricsFileName: String?) {
        self.title = song.title
        self.artist = song.artist
        self.album = song.album
        self.duration = song.duration
        self.format = song.metadata.format
        self.sampleRate = song.metadata.sampleRate
        self.bitRate = song.metadata.bitRate
        self.channels = song.metadata.channels
        self.trackNumber = song.metadata.trackNumber
        self.year = song.metadata.year
        self.genre = song.metadata.genre
        self.audioFileName = audioFileName
        self.coverFileName = coverFileName
        self.lyricsFileName = lyricsFileName
    }
}

struct PlaylistExportData: Codable {
    let name: String
    let description: String?
    let groupName: String?
    let coverFileName: String?
    let songs: [SongExportData]
    let sortOrder: Int
}

// MARK: - 匹配

enum SongMatchResult {
    case exactMatch(Song)
    case fuzzyMatch(Song)
    case noMatch
}

// MARK: - 分享会话

struct ShareSessionInfo: Codable {
    let deviceName: String
    let sessionToken: String
    let songCount: Int
    let playlistCount: Int
    let totalSize: Int64
}

struct ShareSongSummary: Codable, Identifiable {
    let index: Int
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let fileSize: Int64
    let hasCover: Bool
    let hasLyrics: Bool

    var id: Int { index }
}

struct SharePlaylistSummary: Codable, Identifiable {
    let index: Int
    let name: String
    let description: String?
    let groupName: String?
    let songCount: Int

    var id: Int { index }
}

// MARK: - 分享分析与结果

struct ShareAnalysis {
    let sessionInfo: ShareSessionInfo
    let songs: [ShareSongSummary]
    let playlists: [SharePlaylistSummary]
    let newSongs: [ShareSongSummary]
    let exactMatchSongs: [ShareSongSummary]
    let fuzzyMatchSongs: [ShareSongSummary]
    let playlistLocalSongs: [String: Int]
    let estimatedDownloadSize: Int64

    var skippedSongs: [ShareSongSummary] { exactMatchSongs + fuzzyMatchSongs }
}

struct ShareTransferResult: Codable {
    let songsReceived: Int
    let songsSkipped: Int
    let playlistsCreated: Int
    let localSongsLinked: Int
    let failedCount: Int
}

// MARK: - 分享进度

struct ShareProgress {
    let phase: SharePhase
    let current: Int
    let total: Int
    let currentFileName: String?

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

enum SharePhase {
    case preparing
    case transferring
    case importing
    case completed
    case failed(String)

    var label: String {
        switch self {
        case .preparing: return "准备中..."
        case .transferring: return "传输中..."
        case .importing: return "导入中..."
        case .completed: return "完成"
        case .failed(let msg): return "失败: \(msg)"
        }
    }
}

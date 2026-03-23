import Foundation

struct ArtistGroup: Identifiable, Hashable {
    let name: String
    let songCount: Int
    let albumCount: Int
    /// id 使用艺术家名称，假定名称在数据库中唯一；如果不同来源存在同名艺术家，需要额外区分键。
    var id: String { name }

    static func group(from songs: [Song]) -> [ArtistGroup] {
        var groups: [String: (songCount: Int, albums: Set<String>)] = [:]
        for song in songs {
            var g = groups[song.artist] ?? (0, [])
            g.songCount += 1
            g.albums.insert(song.album)
            groups[song.artist] = g
        }
        return groups
            .map { ArtistGroup(name: $0.key, songCount: $0.value.songCount, albumCount: $0.value.albums.count) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
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

    static func group(from songs: [Song]) -> [AlbumGroup] {
        var groups: [AlbumKey: (year: Int?, count: Int, cover: String?)] = [:]
        for song in songs {
            let key = AlbumKey(artist: song.artist, album: song.album)
            var g = groups[key] ?? (song.metadata.year, 0, song.coverImagePath)
            g.count += 1
            groups[key] = g
        }
        return groups
            .map { AlbumGroup(name: $0.key.album, artist: $0.key.artist,
                              year: $0.value.year, songCount: $0.value.count,
                              coverImagePath: $0.value.cover) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
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

enum PlayContext {
    case allSongs(sortBy: SongSortOption)
    case album(name: String, artist: String)
    case artist(name: String)
    case playlist(id: UUID)
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

@MainActor
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

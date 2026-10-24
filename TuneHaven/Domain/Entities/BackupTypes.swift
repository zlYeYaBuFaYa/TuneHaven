import Foundation

enum BackupPackageFormat {
    static let version = 1
    static let fileExtension = "tunehaven"
    static let typeIdentifier = "com.tunehaven.backup"
    static let manifestFile = "manifest.json"
    static let preferencesFile = "preferences.json"
    static let groupsFile = "groups.json"
    static let playlistsFile = "playlists.json"
    static let songsFile = "songs.json"
    static let audioDirectory = "audio"
    static let coverDirectory = "covers"
    static let lyricsDirectory = "lyrics"
    /// 主匹配允许的时长差。与分享直传一致，严格小于 2 秒。
    static let durationMatchTolerance: TimeInterval = 2
    /// ZIP32 中央目录偏移上限。超出后拒绝导出，提示改用仅元数据。
    static let maxZipOffset: UInt64 = UInt64(UInt32.max) - 65_536
}

enum BackupRestoreMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case merge
    case replaceLibrary
    case preferencesOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "合并"
        case .replaceLibrary: return "替换曲库"
        case .preferencesOnly: return "仅恢复偏好"
        }
    }

    var detail: String {
        switch self {
        case .merge: return "保留现有曲库，按冲突选项处理重名歌曲和歌单"
        case .replaceLibrary: return "清空自建曲库和自建歌单后再导入"
        case .preferencesOnly: return "只恢复主题和播放设置，不动歌曲和歌单"
        }
    }
}

enum BackupSongConflictChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case replace
    case skip
    case saveCopy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replace: return "替换"
        case .skip: return "跳过"
        case .saveCopy: return "另存副本"
        }
    }
}

enum BackupPlaylistConflictChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case replace
    case merge
    case saveCopy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replace: return "替换"
        case .merge: return "合并"
        case .saveCopy: return "新建副本"
        }
    }
}

struct BackupConflictResolution: Equatable, Sendable {
    var songChoice: BackupSongConflictChoice
    var playlistChoice: BackupPlaylistConflictChoice
    var applySongChoiceToAll: Bool
    var applyPlaylistChoiceToAll: Bool
    var songOverrides: [UUID: BackupSongConflictChoice]
    var playlistOverrides: [UUID: BackupPlaylistConflictChoice]

    static let recommended = BackupConflictResolution(
        songChoice: .skip,
        playlistChoice: .merge,
        applySongChoiceToAll: true,
        applyPlaylistChoiceToAll: true,
        songOverrides: [:],
        playlistOverrides: [:]
    )

    func songChoice(for id: UUID) -> BackupSongConflictChoice {
        if applySongChoiceToAll { return songChoice }
        return songOverrides[id] ?? songChoice
    }

    func playlistChoice(for id: UUID) -> BackupPlaylistConflictChoice {
        if applyPlaylistChoiceToAll { return playlistChoice }
        return playlistOverrides[id] ?? playlistChoice
    }
}

struct BackupManifest: Codable, Equatable, Sendable {
    var formatVersion: Int
    var appVersion: String
    var exportedAt: Date
    var includesAudio: Bool
    var songCount: Int
    var playlistCount: Int
    var groupCount: Int
    var payloadBytes: Int64
}

struct BackupPreferences: Codable, Equatable, Sendable {
    var themeStyle: String?
    var playMode: Int?
    var speedMemoryMode: Int?
    var lyricsPreferSimplified: Bool?
}

struct BackupSongRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var fileHash: String
    var fileSize: Int64
    var format: String
    var sampleRate: Int?
    var bitRate: Int?
    var channels: Int?
    var encoder: String?
    var trackNumber: Int?
    var year: Int?
    var genre: String?
    var audioEntry: String?
    var coverEntry: String?
    var lyricsEntry: String?
    var lyricsSource: Int?
    var isFavorite: Bool
    var favoriteDate: Date?
    var importDate: Date
}

struct BackupPlaylistRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var description: String?
    var groupName: String?
    var sortOrder: Int
    var songIds: [UUID]
}

struct BackupGroupRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var sortOrder: Int
}

struct BackupCatalog: Codable, Equatable, Sendable {
    var manifest: BackupManifest
    var preferences: BackupPreferences
    var groups: [BackupGroupRecord]
    var playlists: [BackupPlaylistRecord]
    var songs: [BackupSongRecord]
}

struct BackupLibrarySong: Equatable, Sendable, Identifiable {
    var song: Song
    var id: UUID { song.id }
}

struct BackupLibraryPlaylist: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var description: String?
    var isSystem: Bool
    var systemTypeRaw: Int16
    var groupId: UUID?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var songIds: [UUID]
}

struct BackupLibraryGroup: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
}

struct BackupLibrarySnapshot: Equatable, Sendable {
    var songs: [BackupLibrarySong]
    var playlists: [BackupLibraryPlaylist]
    var groups: [BackupLibraryGroup]
    var preferences: BackupPreferences

    func libraryBodyEquals(_ other: BackupLibrarySnapshot) -> Bool {
        songs == other.songs && playlists == other.playlists && groups == other.groups
    }
}

protocol BackupLibraryApplying: AnyObject, Sendable {
    func loadSnapshot() async throws -> BackupLibrarySnapshot
    func apply(_ snapshot: BackupLibrarySnapshot) async throws
}

enum BackupStoredFile: Equatable, Sendable {
    case music(relativePath: String)
    case lyrics(relativePath: String)
    case cover(key: String)
}

struct BackupPlannedCopy: Equatable, Sendable {
    var sourceEntry: String
    var destination: BackupStoredFile
    var librarySongId: UUID
    /// 歌词文件复制成功后才写入歌曲。封面和音频不使用这个字段。
    var lyricsSource: LyricsSource? = nil
}

struct BackupRestoreSummary: Equatable, Sendable {
    var songsAdded: Int = 0
    var songsReplaced: Int = 0
    var songsSkipped: Int = 0
    var songsDuplicated: Int = 0
    var songsMissingAudio: Int = 0
    var playlistsAdded: Int = 0
    var playlistsReplaced: Int = 0
    var playlistsMerged: Int = 0
    var playlistsDuplicated: Int = 0
    var playlistsSkipped: Int = 0
    var preferencesRestored: Bool = false

    var songsSucceeded: Int { songsAdded + songsReplaced + songsDuplicated }
}

struct BackupCommitPlan: Equatable, Sendable {
    var snapshot: BackupLibrarySnapshot
    var copies: [BackupPlannedCopy]
    var summary: BackupRestoreSummary
}

struct BackupNamedConflict: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var detail: String
}

struct BackupPreview: Equatable, Sendable {
    var manifest: BackupManifest
    var songConflicts: [BackupNamedConflict]
    var playlistConflicts: [BackupNamedConflict]
}

struct BackupProgress: Equatable, Sendable {
    var phase: String
    var completed: Int
    var total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

struct BackupFileLayout: Equatable, Sendable {
    var musicDirectory: URL
    var lyricsDirectory: URL
    var coverDirectory: URL

    func url(for file: BackupStoredFile) -> URL {
        switch file {
        case .music(let relativePath):
            return Self.appendingRelativePath(relativePath, to: musicDirectory)
        case .lyrics(let relativePath):
            return Self.appendingRelativePath(relativePath, to: lyricsDirectory)
        case .cover(let key):
            return coverDirectory.appendingPathComponent(Self.sanitize(key))
        }
    }

    /// 按 `/` 逐段拼接。`appendingPathComponent` 会把斜杠编码进单个路径组件。
    static func appendingRelativePath(_ relativePath: String, to root: URL) -> URL {
        let parts = relativePath.split(separator: "/").map(String.init).filter { part in
            !part.isEmpty && part != "." && part != ".."
        }
        return parts.reduce(root) { $0.appendingPathComponent($1) }
    }

    func relativePath(of url: URL, under root: URL) -> String {
        let prefix = Self.directoryPrefix(root)
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }

    static func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }

    private static func directoryPrefix(_ root: URL) -> String {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasSuffix("/") ? path : path + "/"
    }
}

struct BackupExportFile: Equatable, Sendable {
    var sourceURL: URL
    var entryPath: String
    var byteCount: Int64
}

struct BackupExportDraft: Equatable, Sendable {
    var catalog: BackupCatalog
    var files: [BackupExportFile]
}

enum BackupByteCount {
    static func format(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}

enum BackupJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

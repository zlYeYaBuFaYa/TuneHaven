import Foundation

// MARK: - 导出内容类型

enum SyncContentType: String, Codable {
    case songs = "songs"
    case playlists = "playlists"
    case playlistsWithAudio = "playlists_with_audio"
}

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

// MARK: - 包清单

struct TuneHavenManifest: Codable {
    let version: Int
    let exportDate: Date
    let contentType: SyncContentType
    let deviceName: String
    let songs: [SongExportData]?
    let playlists: [PlaylistExportData]?

    init(
        exportDate: Date = Date(),
        contentType: SyncContentType,
        deviceName: String,
        songs: [SongExportData]? = nil,
        playlists: [PlaylistExportData]? = nil
    ) {
        self.version = 1
        self.exportDate = exportDate
        self.contentType = contentType
        self.deviceName = deviceName
        self.songs = songs
        self.playlists = playlists
    }
}

// MARK: - 匹配与冲突

enum SongMatchResult {
    case exactMatch(Song)
    case fuzzyMatch(Song)
    case noMatch
}

enum SongConflictResolution {
    case replace
    case skip
    case saveAsCopy
}

enum PlaylistConflictResolution {
    case replace
    case merge
    case createCopy
}

struct SongConflict: Identifiable {
    let id = UUID()
    let incoming: SongExportData
    let existing: Song
    var resolution: SongConflictResolution?
}

struct PlaylistConflict: Identifiable {
    let id = UUID()
    let incoming: PlaylistExportData
    let existing: Playlist
    var resolution: PlaylistConflictResolution?
}

// MARK: - 进度与结果

struct SyncProgress {
    let phase: SyncPhase
    let current: Int
    let total: Int
    let currentFileName: String?

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

enum SyncPhase {
    case preparing
    case exporting
    case transferring
    case importing
    case matching
    case completed
    case failed(String)
}

struct SyncImportResult {
    let songsImported: Int
    let songsSkipped: Int
    let songsFailed: Int
    let playlistsImported: Int
    let playlistsSkipped: Int
    let missingSongsCount: Int
}

struct SyncAnalysisResult {
    let manifest: TuneHavenManifest
    let extractedDir: URL
    let songConflicts: [SongConflict]
    let playlistConflicts: [PlaylistConflict]
    let newSongsCount: Int
    let newPlaylistsCount: Int
    let estimatedImportSize: Int64
}

// MARK: - 缺失歌曲引用

struct MissingSongReference: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let playlistId: UUID

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        playlistId: UUID
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.playlistId = playlistId
    }
}

import Foundation

enum SandboxPathManager {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var musicURL: URL {
        documentsURL.appendingPathComponent("Music", isDirectory: true)
    }

    static var lyricsURL: URL {
        documentsURL.appendingPathComponent("Lyrics", isDirectory: true)
    }

    static var cachesURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// 日志放在 Caches：不进 iCloud 备份，空间不足时可被系统清理。
    static func logFileURL(named name: String) -> URL {
        cachesURL.appendingPathComponent(name)
    }

    /// 旧版本写在 Documents 的日志（会进 iCloud 备份），启动时删除。
    static func removeLegacyLogs() {
        let fm = FileManager.default
        for name in ["app.log", "app.log.old", "error.log", "error.log.old"] {
            let url = documentsURL.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// 歌曲封面的唯一存储。不放 Caches，避免被系统或清理操作删除。
    static var coverImagesURL: URL {
        applicationSupportURL.appendingPathComponent("CoverImages", isDirectory: true)
    }

    /// 歌单封面（自定义与自动拼图）的唯一存储。
    static var playlistCoversURL: URL {
        applicationSupportURL.appendingPathComponent("PlaylistCovers", isDirectory: true)
    }

    /// 旧版本的封面目录，只供 `CoverStorageMigration` 迁移使用。
    static var legacyCoverImagesURL: URL {
        cachesURL.appendingPathComponent("CoverImages", isDirectory: true)
    }

    static var legacyPlaylistCoversURL: URL {
        cachesURL.appendingPathComponent("PlaylistCovers", isDirectory: true)
    }

    static var tmpURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    static var pendingDeleteURL: URL {
        tmpURL.appendingPathComponent("pending_delete", isDirectory: true)
    }

    static var wifiUploadURL: URL {
        tmpURL.appendingPathComponent("wifi_upload", isDirectory: true)
    }

    static var importTempURL: URL {
        tmpURL.appendingPathComponent("import_temp", isDirectory: true)
    }

    static var exportTempURL: URL {
        tmpURL.appendingPathComponent("export_temp", isDirectory: true)
    }

    static var syncExtractURL: URL {
        tmpURL.appendingPathComponent("sync_extract", isDirectory: true)
    }

    static var backupExtractURL: URL {
        tmpURL.appendingPathComponent("backup_extract", isDirectory: true)
    }

    static var backupExportURL: URL {
        tmpURL.appendingPathComponent("backup_export", isDirectory: true)
    }

    static var backupIncomingURL: URL {
        tmpURL.appendingPathComponent("backup_incoming", isDirectory: true)
    }

    static func createAllDirectories() {
        let fm = FileManager.default
        let dirs = [musicURL, lyricsURL, coverImagesURL, playlistCoversURL,
                    pendingDeleteURL, wifiUploadURL, importTempURL,
                    exportTempURL, syncExtractURL, backupExtractURL,
                    backupExportURL, backupIncomingURL]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    ErrorLogger.shared.logGeneric(error, context: "目录创建失败: \(dir.lastPathComponent)")
                }
            }
        }
    }

    static func musicFileURL(relativePath: String) -> URL {
        musicURL.appendingPathComponent(relativePath)
    }

    static func lyricsFileURL(relativePath: String) -> URL {
        lyricsURL.appendingPathComponent(relativePath)
    }

    static func coverImageURL(songId: UUID, size: ThumbnailSize) -> URL {
        coverImagesURL.appendingPathComponent("\(songId.uuidString)_\(size.suffix).jpg")
    }

    static func playlistCoverURL(playlistId: UUID) -> URL {
        playlistCoversURL.appendingPathComponent("\(playlistId.uuidString).jpg")
    }
}

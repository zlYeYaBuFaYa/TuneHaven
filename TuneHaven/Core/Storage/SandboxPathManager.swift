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

    static var coverImagesURL: URL {
        cachesURL.appendingPathComponent("CoverImages", isDirectory: true)
    }

    static var playlistCoversURL: URL {
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

    static func createAllDirectories() {
        let fm = FileManager.default
        let dirs = [musicURL, lyricsURL, coverImagesURL, playlistCoversURL,
                    pendingDeleteURL, wifiUploadURL, importTempURL,
                    exportTempURL, syncExtractURL]
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

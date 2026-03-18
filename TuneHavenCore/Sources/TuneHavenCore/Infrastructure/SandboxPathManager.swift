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

    static func createAllDirectories() {
        let fm = FileManager.default
        let dirs = [musicURL, lyricsURL, coverImagesURL, playlistCoversURL,
                    pendingDeleteURL, wifiUploadURL, importTempURL]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
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

enum ThumbnailSize: String {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case original = "original"

    var suffix: String { rawValue }

    var dimension: CGFloat {
        switch self {
        case .small: return 100
        case .medium: return 200
        case .large: return 400
        case .original: return 1024
        }
    }
}

import Foundation

struct WebDAVFile: Identifiable, Hashable {
    let href: String
    let displayName: String
    let contentLength: Int64
    let contentType: String?
    let lastModified: Date?
    let isDirectory: Bool
    let etag: String?

    var id: String { href }

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "alac", "wav", "flac", "aiff", "aif", "caf"
    ]

    var isAudio: Bool {
        guard !isDirectory else { return false }
        let ext = (fileName as NSString).pathExtension.lowercased()
        return Self.audioExtensions.contains(ext)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: contentLength, countStyle: .file)
    }

    var fileName: String {
        if !displayName.isEmpty { return displayName }
        let last = (href as NSString).lastPathComponent
        return last.removingPercentEncoding ?? last
    }
}

struct WebDAVDownloadTask: Identifiable {
    let id: UUID
    let file: WebDAVFile
    var status: DownloadStatus
    var bytesReceived: Int64
    var totalBytes: Int64
    var error: String?

    enum DownloadStatus {
        case waiting
        case downloading
        case completed(localURL: URL)
        case failed
        case skippedOversize
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }
}

struct WebDAVImportResult {
    let downloadedCount: Int
    let downloadFailedCount: Int
    let skippedOversizeCount: Int
    let importResult: ImportResult?
    let errors: [String]

    var totalSelected: Int {
        downloadedCount + downloadFailedCount + skippedOversizeCount
    }
}

import Foundation

extension Song {
    func formatDuration() -> String {
        DurationFormatter.format(duration)
    }

    func formatFileSize() -> String {
        let mb = Double(fileSize) / 1024 / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if fileSize >= 1024 { return String(format: "%d KB", fileSize / 1024) }
        if fileSize > 0 { return "< 1 KB" }
        return "0 KB"
    }
}

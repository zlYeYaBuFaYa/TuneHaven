import Foundation

extension Song {
    func formatDuration() -> String {
        DurationFormatter.format(duration)
    }

    func formatFileSize() -> String {
        let mb = Double(fileSize) / 1024 / 1024
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%d KB", fileSize / 1024)
    }
}

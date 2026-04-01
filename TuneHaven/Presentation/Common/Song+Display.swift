import Foundation

extension Song {
    func formatDuration() -> String {
        DurationFormatter.format(duration)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

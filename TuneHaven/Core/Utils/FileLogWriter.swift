import Foundation

final class FileLogWriter {
    private let writeQueue: DispatchQueue
    private let fileURL: () -> URL
    private let maxFileSize: Int64
    private let backupSuffix: String

    static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func isoDate() -> String {
        dateFormatter.string(from: Date())
    }

    init(queueLabel: String, fileURL: @escaping () -> URL, maxFileSize: Int64 = 5 * 1024 * 1024, backupSuffix: String = ".old") {
        self.writeQueue = DispatchQueue(label: queueLabel, qos: .utility)
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        self.backupSuffix = backupSuffix
    }

    func write(_ entry: String) {
        guard let data = entry.data(using: .utf8) else { return }
        let url = fileURL()
        writeQueue.async {
            self.rotateIfNeeded(url: url)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func rotateIfNeeded(url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if size > maxFileSize {
            let backupURL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + backupSuffix)
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: url, to: backupURL)
        }
    }
}

import Foundation
import CryptoKit

final class FileStorageService {
    static let shared = FileStorageService()
    private init() {}
    private let log = AppLogger.shared

    static let maxFileSizeBytes: Int64 = 500 * 1024 * 1024
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "alac", "wav", "flac", "aiff", "aif", "caf"]

    func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func copyToMusic(from sourceURL: URL, fileHash: String, originalFileName: String) throws -> String {
        log.info("复制文件到音乐目录: \(originalFileName)")
        let shortHash = String(fileHash.prefix(8))
        let safeName = sanitizeFileName(originalFileName)
        let relativePath = "\(shortHash)_\(safeName)"
        let destURL = SandboxPathManager.musicFileURL(relativePath: relativePath)

        if !FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
        return relativePath
    }

    func moveToPendingDelete(relativePath: String) throws -> String {
        let srcURL = SandboxPathManager.musicFileURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: srcURL.path) else { return relativePath }
        log.info("移动到待删除目录: \(relativePath)")
        let destURL = SandboxPathManager.pendingDeleteURL.appendingPathComponent((relativePath as NSString).lastPathComponent)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: srcURL, to: destURL)
        return (relativePath as NSString).lastPathComponent
    }

    func restoreFromPendingDelete(fileName: String, originalRelativePath: String) throws {
        let srcURL = SandboxPathManager.pendingDeleteURL.appendingPathComponent(fileName)
        let destURL = SandboxPathManager.musicFileURL(relativePath: originalRelativePath)
        guard FileManager.default.fileExists(atPath: srcURL.path) else { return }
        try FileManager.default.moveItem(at: srcURL, to: destURL)
    }

    func deleteFromPendingDelete(fileName: String) {
        let url = SandboxPathManager.pendingDeleteURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    func cleanupPendingDeleteDirectory() {
        log.info("清理待删除目录")
        let url = SandboxPathManager.pendingDeleteURL
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: url.appendingPathComponent(file))
        }
    }

    func fileExists(relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: SandboxPathManager.musicFileURL(relativePath: relativePath).path)
    }

    func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}

extension FileStorageService: FileStorageProviding {
    var maxFileSizeBytes: Int64 { Self.maxFileSizeBytes }
    var supportedExtensions: Set<String> { Self.supportedExtensions }
    var importTempURL: URL { SandboxPathManager.importTempURL }

    func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

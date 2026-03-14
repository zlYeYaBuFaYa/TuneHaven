import Foundation
import UIKit

@MainActor
final class ImportService: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var progress: ImportProgress?

    private let songRepo = CoreDataSongRepository()
    private let fileService = FileStorageService.shared
    private var isCancelled = false

    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
        isImporting = true
        isCancelled = false
        var results: [SingleImportResult] = []
        var successCount = 0
        var skippedDuplicateCount = 0
        var skippedFormatCount = 0
        var failedCount = 0
        var incompleteMetadataCount = 0
        var skippedOversizeCount = 0

        let total = urls.count
        let start = Date()

        for (i, url) in urls.enumerated() {
            if isCancelled { break }

            let fileName = url.lastPathComponent
            let currentProgress = ImportProgress(
                currentFileName: fileName,
                completedCount: i,
                totalCount: total,
                percentage: Double(i) / Double(total),
                estimatedRemainingSeconds: estimateRemaining(start: start, done: i, total: total)
            )
            onProgress(currentProgress)

            let result = await processFile(url: url)
            results.append(result)

            switch result.status {
            case .success: successCount += 1
            case .successIncompleteMetadata: successCount += 1; incompleteMetadataCount += 1
            case .skippedDuplicate: skippedDuplicateCount += 1
            case .skippedUnsupportedFormat: skippedFormatCount += 1
            case .skippedOversize: skippedOversizeCount += 1
            case .failed: failedCount += 1
            }
        }

        isImporting = false
        progress = nil
        return ImportResult(
            successCount: successCount,
            skippedDuplicateCount: skippedDuplicateCount,
            skippedFormatCount: skippedFormatCount,
            failedCount: failedCount,
            incompleteMetadataCount: incompleteMetadataCount,
            skippedOversizeCount: skippedOversizeCount,
            details: results
        )
    }

    func cancelImport() { isCancelled = true }

    func processWiFiFile(tempURL: URL, originalFilename: String) async -> SingleImportResult {
        return await processFile(url: tempURL, overrideName: originalFilename)
    }

    private func processFile(url: URL, overrideName: String? = nil) async -> SingleImportResult {
        let fileName = overrideName ?? url.lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()

        guard FileStorageService.supportedExtensions.contains(ext) else {
            return SingleImportResult(fileName: fileName, status: .skippedUnsupportedFormat, song: nil, errorMessage: "格式不支持：\(ext)")
        }

        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let fileSize = fileService.fileSize(at: url)
        guard fileSize <= FileStorageService.maxFileSizeBytes else {
            return SingleImportResult(fileName: fileName, status: .skippedOversize, song: nil, errorMessage: "文件过大（超过500MB）")
        }

        let hash: String
        do { hash = try fileService.sha256(of: url) } catch {
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件读取失败")
        }

        if let existing = await songRepo.fetchByHash(hash) {
            return SingleImportResult(fileName: fileName, status: .skippedDuplicate, song: existing, errorMessage: nil)
        }

        let parsed = await AudioMetadataParser.shared.parse(url: url)

        let relPath: String
        do { relPath = try fileService.copyToMusic(from: url, fileHash: hash, originalFileName: fileName) } catch {
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件复制失败")
        }

        var coverImagePath: String? = nil
        if let coverImage = parsed.coverImage {
            let songId = UUID()
            let mediumThumb = ThumbnailGenerator.resize(coverImage, to: .medium)
            let cacheURL = SandboxPathManager.coverImageURL(songId: songId, size: .medium)
            if let data = mediumThumb.jpegData(compressionQuality: 0.85) {
                try? data.write(to: cacheURL)
                coverImagePath = "\(songId.uuidString)_medium.jpg"
                ImageCacheManager.shared.store(image: mediumThumb, forKey: coverImagePath!)
            }
        }

        let song = Song(
            id: UUID(),
            title: parsed.title,
            artist: parsed.artist,
            album: parsed.album,
            duration: parsed.duration,
            fileHash: hash,
            fileRelativePath: relPath,
            coverImagePath: coverImagePath,
            lyricsPath: nil,
            lyricsSource: nil,
            metadata: Metadata(
                format: parsed.format,
                sampleRate: parsed.sampleRate,
                bitRate: parsed.bitRate,
                channels: parsed.channels,
                encoder: parsed.encoder,
                trackNumber: parsed.trackNumber,
                year: parsed.year,
                genre: parsed.genre
            ),
            importDate: Date(),
            fileSize: fileSize,
            playCount: 0,
            isFavorite: false,
            favoriteDate: nil,
            lastPlayedDate: nil
        )

        do {
            try await songRepo.insert(song: song)
            return SingleImportResult(fileName: fileName, status: parsed.isIncomplete ? .successIncompleteMetadata : .success, song: song, errorMessage: nil)
        } catch {
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: error.localizedDescription)
        }
    }

    private func estimateRemaining(start: Date, done: Int, total: Int) -> TimeInterval? {
        guard done > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let perItem = elapsed / Double(done)
        return perItem * Double(total - done)
    }
}

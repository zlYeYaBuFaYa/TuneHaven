import Foundation
import UIKit

@MainActor
final class ImportService: ObservableObject {
    private let log = AppLogger.shared
    private let log = AppLogger.shared

    @Published private(set) var isImporting = false
    @Published private(set) var progress: ImportProgress?

    private let songRepo = CoreDataSongRepository()
    private let fileService = FileStorageService.shared
    private var isCancelled = false

    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
        log.info("开始导入 \(urls.count) 个文件")
        log.info("开始导入 \(urls.count) 个文件")
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
        log.info("导入完成: 成功=\(successCount), 重复=\(skippedDuplicateCount), 格式不支持=\(skippedFormatCount), 超限=\(skippedOversizeCount), 失败=\(failedCount)")
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

    func cancelImport() {
        log.info("用户取消导入")
        isCancelled = true
    }

    func processWiFiFile(tempURL: URL, originalFilename: String) async -> SingleImportResult {
        return await processFile(url: tempURL, overrideName: originalFilename)
    }

    func processAppleMusicFile(tempURL: URL, originalFilename: String, title: String?, artist: String?, album: String?, coverImage: UIImage?) async -> SingleImportResult {
        return await processFile(url: tempURL, overrideName: originalFilename, titleOverride: title, artistOverride: artist, albumOverride: album, coverOverride: coverImage)
    }

    private func processFile(url: URL, overrideName: String? = nil, titleOverride: String? = nil, artistOverride: String? = nil, albumOverride: String? = nil, coverOverride: UIImage? = nil) async -> SingleImportResult {
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
            log.error(error, context: "文件哈希计算失败: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件读取失败")
        }

        if let existing = await songRepo.fetchByHash(hash) {
            return SingleImportResult(fileName: fileName, status: .skippedDuplicate, song: existing, errorMessage: nil)
        }

        let parsed = await AudioMetadataParser.shared.parse(url: url)

        let finalTitle = titleOverride ?? parsed.title
        let finalArtist = artistOverride ?? parsed.artist
        let finalAlbum = albumOverride ?? parsed.album
        let finalCover = coverOverride ?? parsed.coverImage
        let isIncomplete = parsed.isIncomplete && titleOverride == nil

        let relPath: String
        do { relPath = try fileService.copyToMusic(from: url, fileHash: hash, originalFileName: fileName) } catch {
            log.error(error, context: "文件复制失败: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件复制失败")
        }

        var coverImagePath: String? = nil
        if let coverImage = finalCover {
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
            title: finalTitle,
            artist: finalArtist,
            album: finalAlbum,
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
            return SingleImportResult(fileName: fileName, status: isIncomplete ? .successIncompleteMetadata : .success, song: song, errorMessage: nil)
        } catch {
            log.error(error, context: "歌曲入库失败: \(fileName)")
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

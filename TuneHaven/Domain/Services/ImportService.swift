import Foundation
import UIKit

@MainActor
final class ImportService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var isImporting = false
    @Published private(set) var progress: ImportProgress?

    private let songRepo: SongRepository
    private let fileService: FileStorageService

    init(songRepo: SongRepository,
         fileService: FileStorageService) {
        self.songRepo = songRepo
        self.fileService = fileService
    }
    private var isCancelled = false

    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
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
            self.progress = currentProgress
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
        let coverData = coverImage?.jpegData(compressionQuality: 1.0)
        return await processFile(url: tempURL, overrideName: originalFilename, titleOverride: title, artistOverride: artist, albumOverride: album, coverDataOverride: coverData)
    }

    private func processFile(url: URL, overrideName: String? = nil, titleOverride: String? = nil, artistOverride: String? = nil, albumOverride: String? = nil, coverDataOverride: Data? = nil) async -> SingleImportResult {
        let fileName = overrideName ?? url.lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()
        log.info("[Import] processFile start: \(fileName) ext=\(ext)")

        guard FileStorageService.supportedExtensions.contains(ext) else {
            log.info("[Import] 格式不支持: \(ext)")
            return SingleImportResult(fileName: fileName, status: .skippedUnsupportedFormat, song: nil, errorMessage: "格式不支持：\(ext)")
        }

        let hasAccess = url.startAccessingSecurityScopedResource()
        log.info("[Import] securityScopedAccess=\(hasAccess) url=\(url.path)")
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let fileSize = fileService.fileSize(at: url)
        log.info("[Import] fileSize=\(fileSize) bytes")
        guard fileSize <= FileStorageService.maxFileSizeBytes else {
            return SingleImportResult(fileName: fileName, status: .skippedOversize, song: nil, errorMessage: "文件过大（超过500MB）")
        }

        let hash: String
        do {
            hash = try fileService.sha256(of: url)
            log.info("[Import] sha256 done: \(hash.prefix(12))...")
        } catch {
            log.error(error, context: "[Import] 文件哈希计算失败: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件读取失败")
        }

        if let existing = await songRepo.fetchByHash(hash) {
            log.info("[Import] 跳过重复: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .skippedDuplicate, song: existing, errorMessage: nil)
        }

        log.info("[Import] 开始解析元数据: \(fileName)")
        let parsed = await AudioMetadataParser.shared.parse(url: url)
        log.info("[Import] 元数据解析完成: title=\(parsed.title) artist=\(parsed.artist) duration=\(parsed.duration)")

        let finalTitle = titleOverride ?? parsed.title
        let finalArtist = artistOverride ?? parsed.artist
        let finalAlbum = albumOverride ?? parsed.album
        let finalCoverData = coverDataOverride ?? parsed.coverImageData
        let isIncomplete = parsed.isIncomplete && titleOverride == nil

        let relPath: String
        do {
            relPath = try fileService.copyToMusic(from: url, fileHash: hash, originalFileName: fileName)
            log.info("[Import] 文件复制完成: \(relPath)")
        } catch {
            log.error(error, context: "[Import] 文件复制失败: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件复制失败")
        }

        let songId = UUID()
        var coverImagePath: String? = nil
        if let coverData = finalCoverData, let coverImage = UIImage(data: coverData) {
            let mediumThumb = ThumbnailGenerator.resize(coverImage, to: .medium)
            let cacheURL = SandboxPathManager.coverImageURL(songId: songId, size: .medium)
            if let thumbData = mediumThumb.jpegData(compressionQuality: 0.85) {
                do {
                    try thumbData.write(to: cacheURL)
                    coverImagePath = "\(songId.uuidString)_medium.jpg"
                    ImageCacheManager.shared.store(image: mediumThumb, forKey: coverImagePath!)
                } catch {
                    log.error(error, context: "封面图写入失败: \(songId)")
                }
            }
        }

        let song = Song(
            id: songId,
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
            log.info("[Import] 入库成功: \(song.title) id=\(song.id)")
            return SingleImportResult(fileName: fileName, status: isIncomplete ? .successIncompleteMetadata : .success, song: song, errorMessage: nil)
        } catch {
            log.error(error, context: "[Import] 歌曲入库失败: \(fileName)")
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

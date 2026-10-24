import Foundation

@MainActor
final class ImportService: ObservableObject, FileImporting {
    private let log = AppLogger.shared

    @Published private(set) var isImporting = false
    @Published private(set) var progress: ImportProgress?

    private let songRepo: SongRepository
    private let fileService: FileStorageProviding
    private let coverProcessor: CoverImageProcessing
    private let metadataParser: AudioMetadataParsing
    private let activityGate: BackupActivityGate?

    /// 新歌曲导入成功后的回调，用于触发缺失歌曲恢复等后续逻辑
    var onNewSongsImported: (@MainActor () async -> Void)?

    init(songRepo: SongRepository,
         fileService: FileStorageProviding,
         coverProcessor: CoverImageProcessing,
         metadataParser: AudioMetadataParsing,
         activityGate: BackupActivityGate? = nil) {
        self.songRepo = songRepo
        self.fileService = fileService
        self.coverProcessor = coverProcessor
        self.metadataParser = metadataParser
        self.activityGate = activityGate
    }
    private var isCancelled = false

    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
        log.info("开始导入 \(urls.count) 个文件")
        guard beginExternalImport() else {
            return ImportResult(
                successCount: 0,
                skippedDuplicateCount: 0,
                skippedFormatCount: 0,
                failedCount: max(urls.count, 1),
                incompleteMetadataCount: 0,
                skippedOversizeCount: 0,
                details: [SingleImportResult(fileName: "", status: .failed, song: nil, errorMessage: "已有导入或备份任务正在进行")]
            )
        }
        defer { activityGate?.endImport() }
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

        if successCount > 0 {
            await onNewSongsImported?()
        }

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
        guard beginExternalImport() else {
            return SingleImportResult(fileName: originalFilename, status: .failed, song: nil, errorMessage: "已有导入或备份任务正在进行")
        }
        defer { activityGate?.endImport() }
        return await processFile(url: tempURL, overrideName: originalFilename)
    }

    func processAppleMusicFile(tempURL: URL, originalFilename: String, title: String?, artist: String?, album: String?, coverData: Data?) async -> SingleImportResult {
        guard beginExternalImport() else {
            return SingleImportResult(fileName: originalFilename, status: .failed, song: nil, errorMessage: "已有导入或备份任务正在进行")
        }
        defer { activityGate?.endImport() }
        let overrides = ImportOverrides(title: title, artist: artist, album: album, coverData: coverData)
        return await processFile(url: tempURL, overrideName: originalFilename, overrides: overrides)
    }

    private func beginExternalImport() -> Bool {
        guard let activityGate else { return true }
        do {
            try activityGate.beginImport()
            return true
        } catch {
            log.info("[Import] 与备份任务冲突，拒绝开始")
            return false
        }
    }

    private func processFile(url: URL, overrideName: String? = nil, overrides: ImportOverrides = ImportOverrides()) async -> SingleImportResult {
        let fileName = overrideName ?? url.lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()
        log.info("[Import] processFile start: \(fileName) ext=\(ext)")

        guard fileService.supportedExtensions.contains(ext) else {
            log.info("[Import] 格式不支持: \(ext)")
            return SingleImportResult(fileName: fileName, status: .skippedUnsupportedFormat, song: nil, errorMessage: "格式不支持：\(ext)")
        }

        let hasAccess = url.startAccessingSecurityScopedResource()
        log.info("[Import] securityScopedAccess=\(hasAccess) url=\(url.path)")
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let fileSize = fileService.fileSize(at: url)
        log.info("[Import] fileSize=\(fileSize) bytes")
        guard fileSize <= fileService.maxFileSizeBytes else {
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

        if let existing = await songRepo.fetchByHash(hash), !existing.isAudioMissing {
            log.info("[Import] 跳过重复: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .skippedDuplicate, song: existing, errorMessage: nil)
        }

        log.info("[Import] 开始解析元数据: \(fileName)")
        let parsed = await metadataParser.parse(url: url)
        log.info("[Import] 元数据解析完成: title=\(parsed.title) artist=\(parsed.artist) duration=\(parsed.duration)")

        let finalTitle = overrides.title ?? parsed.title
        let finalArtist = overrides.artist ?? parsed.artist
        let finalAlbum = overrides.album ?? parsed.album
        let finalCoverData = overrides.coverData ?? parsed.coverImageData
        let isIncomplete = parsed.isIncomplete && overrides.title == nil

        if let target = await missingSongTarget(
            hash: hash,
            title: finalTitle,
            artist: finalArtist,
            album: finalAlbum,
            duration: parsed.duration
        ) {
            return await reattachMissingSong(
                target,
                url: url,
                fileName: fileName,
                hash: hash,
                fileSize: fileSize,
                title: finalTitle,
                artist: finalArtist,
                album: finalAlbum,
                parsed: parsed,
                coverData: finalCoverData,
                isIncomplete: isIncomplete
            )
        }

        let relPath: String
        do {
            relPath = try fileService.copyToMusic(from: url, fileHash: hash, originalFileName: fileName)
            log.info("[Import] 文件复制完成: \(relPath)")
        } catch {
            log.error(error, context: "[Import] 文件复制失败: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件复制失败")
        }

        let songId = UUID()
        var coverImagePath: String?
        var coverFailed = false
        if let coverData = finalCoverData {
            do {
                coverImagePath = try await coverProcessor.processSongCover(data: coverData, songId: songId)
            } catch {
                log.error(error, context: "[Import] 封面处理失败: \(fileName)")
                coverFailed = true
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
            return SingleImportResult(fileName: fileName, status: (isIncomplete || coverFailed) ? .successIncompleteMetadata : .success, song: song, errorMessage: nil)
        } catch {
            log.error(error, context: "[Import] 歌曲入库失败: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: error.localizedDescription)
        }
    }

    private func missingSongTarget(
        hash: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> Song? {
        if !hash.isEmpty, let hashed = await songRepo.fetchByHash(hash), hashed.isAudioMissing {
            return hashed
        }
        let missing = await songRepo.fetchSongsMissingAudio()
        return BackupSongMatcher.bestMatch(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            in: missing
        )
    }

    private func reattachMissingSong(
        _ existing: Song,
        url: URL,
        fileName: String,
        hash: String,
        fileSize: Int64,
        title: String,
        artist: String,
        album: String,
        parsed: ParsedMetadata,
        coverData: Data?,
        isIncomplete: Bool
    ) async -> SingleImportResult {
        let relPath: String
        do {
            relPath = try fileService.copyToMusic(from: url, fileHash: hash, originalFileName: fileName)
        } catch {
            log.error(error, context: "[Import] 挂回缺失歌曲失败: \(fileName)")
            return SingleImportResult(fileName: fileName, status: .failed, song: nil, errorMessage: "文件复制失败")
        }
        var coverImagePath = existing.coverImagePath
        var coverFailed = false
        if let coverData {
            do {
                coverImagePath = try await coverProcessor.processSongCover(data: coverData, songId: existing.id)
            } catch {
                coverFailed = true
            }
        }
        let song = Song(
            id: existing.id,
            title: title,
            artist: artist,
            album: album,
            duration: parsed.duration > 0 ? parsed.duration : existing.duration,
            fileHash: hash,
            fileRelativePath: relPath,
            coverImagePath: coverImagePath,
            lyricsPath: existing.lyricsPath,
            lyricsSource: existing.lyricsSource,
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
            importDate: existing.importDate,
            fileSize: fileSize,
            playCount: existing.playCount,
            isFavorite: existing.isFavorite,
            favoriteDate: existing.favoriteDate,
            lastPlayedDate: existing.lastPlayedDate
        )
        do {
            try await songRepo.updateSongMedia(song)
            log.info("[Import] 已挂回缺失歌曲: \(song.title)")
            return SingleImportResult(
                fileName: fileName,
                status: (isIncomplete || coverFailed) ? .successIncompleteMetadata : .success,
                song: song,
                errorMessage: nil
            )
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

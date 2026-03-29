import Foundation

@MainActor
final class OpenInImportHandler {
    private let importService: ImportService
    private let libraryService: MusicLibraryService
    private let fileStorage: FileStorageProviding
    private let snackbar: SnackbarState
    private let log = AppLogger.shared
    var syncImportService: SyncImportService?

    private var queue: [URL] = []
    private var isProcessing = false

    init(importService: ImportService,
         libraryService: MusicLibraryService,
         fileStorage: FileStorageProviding,
         snackbar: SnackbarState) {
        self.importService = importService
        self.libraryService = libraryService
        self.fileStorage = fileStorage
        self.snackbar = snackbar
    }

    func enqueue(url: URL) {
        queue.append(url)
        processNextIfIdle()
    }

    func enqueue(urls: [URL]) {
        queue.append(contentsOf: urls)
        processNextIfIdle()
    }

    private func processNextIfIdle() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        let url = queue.removeFirst()
        Task {
            await handleIncomingFile(url: url)
            isProcessing = false
            processNextIfIdle()
        }
    }

    private func handleIncomingFile(url: URL) async {
        guard fileStorage.fileExists(at: url) else {
            log.info("[OpenIn] 文件不存在，跳过: \(url.lastPathComponent)")
            return
        }

        let fileName = url.lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()

        if ext == "tunehaven" {
            await handleTuneHavenFile(url: url)
            return
        }

        guard fileStorage.supportedExtensions.contains(ext) else {
            snackbar.show(message: "不支持的文件格式：.\(ext)")
            cleanup(url: url)
            return
        }

        let fileSize = fileStorage.fileSize(at: url)
        guard fileSize <= fileStorage.maxFileSizeBytes else {
            snackbar.show(message: "文件超过 500MB 大小限制")
            cleanup(url: url)
            return
        }

        let result = await importService.processWiFiFile(
            tempURL: url, originalFilename: fileName
        )

        cleanup(url: url)

        await libraryService.loadSongs()

        switch result.status {
        case .success, .successIncompleteMetadata:
            let title = result.song?.title ?? fileName
            snackbar.show(message: "已导入「\(title)」")
        case .skippedDuplicate:
            snackbar.show(message: "「\(fileName)」已存在，已跳过")
        case .skippedUnsupportedFormat:
            snackbar.show(message: "不支持的文件格式")
        case .skippedOversize:
            snackbar.show(message: "文件超过大小限制")
        case .failed:
            snackbar.show(message: "导入失败：\(result.errorMessage ?? "未知错误")")
        }
    }

    private func handleTuneHavenFile(url: URL) async {
        guard let syncService = syncImportService else {
            log.info("[OpenIn] syncImportService 未注入，无法处理 .tunehaven 文件")
            snackbar.show(message: "同步服务未就绪，请稍后重试")
            cleanup(url: url)
            return
        }

        do {
            let result = try await syncService.analyze(fileURL: url)
            if result.songConflicts.isEmpty && result.playlistConflicts.isEmpty {
                let importResult = try await syncService.executeImport(
                    analysisResult: result,
                    songResolution: nil,
                    playlistResolution: nil
                )
                await libraryService.loadSongs()
                var msg = "同步导入完成"
                if importResult.songsImported > 0 { msg += "，\(importResult.songsImported) 首歌曲" }
                if importResult.playlistsImported > 0 { msg += "，\(importResult.playlistsImported) 个歌单" }
                snackbar.show(message: msg)
            } else {
                snackbar.show(message: "同步文件包含冲突，请在「同步与传输」中手动导入")
            }
        } catch {
            log.error(error, context: "[OpenIn] .tunehaven 导入失败")
            snackbar.show(message: "同步文件导入失败：\(error.localizedDescription)")
        }

        cleanup(url: url)
    }

    private func cleanup(url: URL) {
        let inboxPath = fileStorage.documentsURL
            .appendingPathComponent("Inbox").path
        guard url.path.hasPrefix(inboxPath) else { return }
        try? fileStorage.removeItem(at: url)
    }

    static func cleanupInbox(fileStorage: FileStorageProviding) {
        let inbox = fileStorage.documentsURL
            .appendingPathComponent("Inbox", isDirectory: true)
        for file in fileStorage.contentsOfDirectory(at: inbox) {
            try? fileStorage.removeItem(at: file)
        }
    }
}

import Foundation

@MainActor
final class OpenInImportHandler {
    private let importService: ImportService
    private let libraryService: MusicLibraryService
    private let snackbar: SnackbarState
    private let log = AppLogger.shared

    private var queue: [URL] = []
    private var isProcessing = false

    init(importService: ImportService,
         libraryService: MusicLibraryService,
         snackbar: SnackbarState) {
        self.importService = importService
        self.libraryService = libraryService
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
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.info("[OpenIn] 文件不存在，跳过: \(url.lastPathComponent)")
            return
        }

        let fileName = url.lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()

        guard FileStorageService.supportedExtensions.contains(ext) else {
            snackbar.show(message: "不支持的文件格式：.\(ext)")
            cleanup(url: url)
            return
        }

        let fileSize = FileStorageService.shared.fileSize(at: url)
        guard fileSize <= FileStorageService.maxFileSizeBytes else {
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

    private func cleanup(url: URL) {
        let inboxPath = SandboxPathManager.documentsURL
            .appendingPathComponent("Inbox").path
        guard url.path.hasPrefix(inboxPath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func cleanupInbox() {
        let inbox = SandboxPathManager.documentsURL
            .appendingPathComponent("Inbox", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

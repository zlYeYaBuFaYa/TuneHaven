import Foundation

@MainActor
final class WebDAVService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var accounts: [WebDAVAccount] = []
    @Published private(set) var currentFiles: [WebDAVFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var downloadTasks: [WebDAVDownloadTask] = []
    @Published private(set) var overallProgress: Double = 0
    @Published private(set) var isDownloading = false

    private let accountStore: WebDAVAccountStoring
    private let clientFactory: WebDAVClientFactory
    private let importService: FileImporting
    private let fileStorage: FileStorageProviding
    private let subscriptionService: SubscriptionService
    private var activeClient: (any WebDAVClientProtocol)?
    private var isCancelRequested = false

    init(accountStore: WebDAVAccountStoring,
         clientFactory: WebDAVClientFactory,
         importService: FileImporting,
         fileStorage: FileStorageProviding,
         subscriptionService: SubscriptionService) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.importService = importService
        self.fileStorage = fileStorage
        self.subscriptionService = subscriptionService
    }

    // MARK: - Account Management

    func loadAccounts() {
        accounts = accountStore.loadAccounts()
    }

    func addAccount(_ account: WebDAVAccount, password: String) throws {
        try accountStore.saveAccount(account, password: password)
        loadAccounts()
    }

    func updateAccount(_ account: WebDAVAccount, password: String?) throws {
        try accountStore.saveAccount(account, password: password)
        loadAccounts()
    }

    func deleteAccount(id: UUID) throws {
        try accountStore.deleteAccount(id: id)
        loadAccounts()
    }

    func password(for accountId: UUID) -> String? {
        accountStore.password(for: accountId)
    }

    func testConnection(account: WebDAVAccount, password: String) async throws -> Bool {
        guard let baseURL = URL(string: account.serverURL) else {
            throw AppError.webdavConnectionFailed("无效的服务器地址")
        }
        let client = clientFactory.makeClient(
            baseURL: baseURL,
            username: account.username,
            password: password,
            trustSelfSignedCert: account.trustSelfSignedCert
        )
        return try await client.testConnection()
    }

    // MARK: - Browse

    func connect(to account: WebDAVAccount) async throws {
        guard subscriptionService.canAccess(.webDAVImport) else {
            throw AppError.featureRequiresPremium(PremiumFeature.webDAVImport.rawValue)
        }
        guard let baseURL = URL(string: account.serverURL) else {
            throw AppError.webdavConnectionFailed("无效的服务器地址")
        }
        guard let password = accountStore.password(for: account.id) else {
            throw AppError.webdavAuthFailed
        }
        activeClient = clientFactory.makeClient(
            baseURL: baseURL,
            username: account.username,
            password: password,
            trustSelfSignedCert: account.trustSelfSignedCert
        )
        try? accountStore.updateLastConnected(accountId: account.id)
        loadAccounts()
        try await loadDirectory("/")
    }

    func loadDirectory(_ path: String) async throws {
        guard let client = activeClient else {
            throw AppError.webdavConnectionFailed("未连接到服务器")
        }
        isLoading = true
        defer { isLoading = false }

        let files = try await client.listDirectory(path: path)
        let filtered = files
            .filter { $0.isDirectory || $0.isAudio }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            }
        currentFiles = filtered
    }

    func disconnect() {
        activeClient = nil
        currentFiles = []
    }

    // MARK: - Download & Import

    private static let maxDownloadConcurrency = 3

    func downloadAndImport(
        files: [WebDAVFile],
        onTaskUpdate: @escaping @MainActor (WebDAVDownloadTask) -> Void
    ) async -> WebDAVImportResult {
        guard subscriptionService.canAccess(.webDAVImport) else {
            let message = AppError.featureRequiresPremium(PremiumFeature.webDAVImport.rawValue).localizedDescription
            return WebDAVImportResult(
                downloadedCount: 0,
                downloadFailedCount: files.count,
                skippedOversizeCount: 0,
                importResult: nil,
                errors: [message]
            )
        }
        guard let client = activeClient else {
            return WebDAVImportResult(downloadedCount: 0, downloadFailedCount: files.count,
                                     skippedOversizeCount: 0, importResult: nil,
                                     errors: ["未连接到服务器"])
        }

        isDownloading = true
        isCancelRequested = false
        var downloadedURLs: [URL] = []
        var failedCount = 0
        var oversizeCount = 0
        var errors: [String] = []
        let total = files.count

        downloadTasks = files.map { file in
            WebDAVDownloadTask(id: UUID(), file: file, status: .waiting,
                               bytesReceived: 0, totalBytes: file.contentLength, error: nil)
        }

        // 每次下载一个临时根目录，每个文件一个序号子目录：同名文件不会互相覆盖，导入时仍用原文件名
        let tempRoot = fileStorage.importTempURL
            .appendingPathComponent("webdav-\(UUID().uuidString)", isDirectory: true)
        try? fileStorage.createDirectoryIfNeeded(at: tempRoot)
        defer { try? fileStorage.removeItem(at: tempRoot) }

        var downloadableIndices: [Int] = []
        for i in 0..<total {
            if files[i].contentLength > fileStorage.maxFileSizeBytes {
                downloadTasks[i].status = .skippedOversize
                oversizeCount += 1
                onTaskUpdate(downloadTasks[i])
            } else {
                downloadableIndices.append(i)
            }
        }

        for i in downloadableIndices {
            downloadTasks[i].status = .downloading
            onTaskUpdate(downloadTasks[i])
        }

        var nextPos = 0
        var downloadResults: [(Int, Result<URL, Error>)] = []

        await withTaskGroup(of: (Int, Result<URL, Error>).self) { group in
            func addNextDownload() {
                guard nextPos < downloadableIndices.count else { return }
                let i = downloadableIndices[nextPos]
                nextPos += 1
                let file = files[i]
                let fileDir = tempRoot.appendingPathComponent("\(i)", isDirectory: true)
                let destURL = fileDir.appendingPathComponent(file.fileName)
                try? fileStorage.createDirectoryIfNeeded(at: fileDir)
                group.addTask { [weak self] in
                    do {
                        _ = try await client.downloadFile(
                            remotePath: file.href,
                            to: destURL
                        ) { [weak self] received, fileTotal in
                            Task { @MainActor [weak self] in
                                guard let self, i < self.downloadTasks.count else { return }
                                self.downloadTasks[i].bytesReceived = received
                                self.downloadTasks[i].totalBytes = fileTotal > 0 ? fileTotal : file.contentLength
                            }
                        }
                        return (i, .success(destURL))
                    } catch {
                        return (i, .failure(error))
                    }
                }
            }

            for _ in 0..<Self.maxDownloadConcurrency where !isCancelRequested { addNextDownload() }
            for await result in group {
                downloadResults.append(result)
                if isCancelRequested {
                    group.cancelAll()
                } else {
                    addNextDownload()
                }
            }
        }

        let cancelled = isCancelRequested
        for (i, result) in downloadResults {
            switch result {
            case .success(let url):
                downloadTasks[i].status = .completed(localURL: url)
                downloadedURLs.append(url)
            case .failure(let error):
                downloadTasks[i].status = .failed
                downloadTasks[i].error = cancelled ? "已取消" : error.localizedDescription
                failedCount += 1
                if !cancelled {
                    errors.append("\(files[i].fileName): \(error.localizedDescription)")
                    log.error(error, context: "WebDAV 下载失败: \(files[i].fileName)")
                }
            }
            onTaskUpdate(downloadTasks[i])
            overallProgress = Double(downloadedURLs.count + failedCount + oversizeCount) / Double(total)
        }

        if cancelled {
            // 取消时还没派发的下载也标为已取消
            let finished = Set(downloadResults.map(\.0))
            for i in downloadableIndices where !finished.contains(i) {
                downloadTasks[i].status = .failed
                downloadTasks[i].error = "已取消"
                failedCount += 1
                onTaskUpdate(downloadTasks[i])
            }
            errors.append("已取消")
            log.info("[WebDAV] 用户取消下载，已下载 \(downloadedURLs.count) 个，不导入")
        }

        overallProgress = 1.0

        var importResult: ImportResult?
        if !cancelled, !downloadedURLs.isEmpty {
            importResult = await importService.importFromFiles(urls: downloadedURLs) { _ in }
        }

        isDownloading = false
        let result = WebDAVImportResult(
            downloadedCount: downloadedURLs.count,
            downloadFailedCount: failedCount,
            skippedOversizeCount: oversizeCount,
            importResult: importResult,
            errors: errors
        )
        return result
    }

    func cancelDownload() {
        isCancelRequested = true
        Task {
            await activeClient?.cancelDownload()
        }
    }
}

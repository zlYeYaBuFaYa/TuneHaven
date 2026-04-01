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
    private var activeClient: (any WebDAVClientProtocol)?
    private var isCancelRequested = false

    init(accountStore: WebDAVAccountStoring,
         clientFactory: WebDAVClientFactory,
         importService: FileImporting,
         fileStorage: FileStorageProviding) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.importService = importService
        self.fileStorage = fileStorage
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

        let tempDir = fileStorage.importTempURL
        try? fileStorage.createDirectoryIfNeeded(at: tempDir)

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
            for _ in 0..<min(Self.maxDownloadConcurrency, downloadableIndices.count) {
                guard nextPos < downloadableIndices.count else { break }
                let i = downloadableIndices[nextPos]
                nextPos += 1
                let file = files[i]
                let destURL = tempDir.appendingPathComponent(file.fileName)
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

            for await result in group {
                downloadResults.append(result)
                if nextPos < downloadableIndices.count {
                    let ni = downloadableIndices[nextPos]
                    nextPos += 1
                    let nextFile = files[ni]
                    let destURL = tempDir.appendingPathComponent(nextFile.fileName)
                    group.addTask { [weak self] in
                        do {
                            _ = try await client.downloadFile(
                                remotePath: nextFile.href,
                                to: destURL
                            ) { [weak self] received, fileTotal in
                                Task { @MainActor [weak self] in
                                    guard let self, ni < self.downloadTasks.count else { return }
                                    self.downloadTasks[ni].bytesReceived = received
                                    self.downloadTasks[ni].totalBytes = fileTotal > 0 ? fileTotal : nextFile.contentLength
                                }
                            }
                            return (ni, .success(destURL))
                        } catch {
                            return (ni, .failure(error))
                        }
                    }
                }
            }
        }

        for (i, result) in downloadResults {
            switch result {
            case .success(let url):
                downloadTasks[i].status = .completed(localURL: url)
                downloadedURLs.append(url)
            case .failure(let error):
                downloadTasks[i].status = .failed
                downloadTasks[i].error = error.localizedDescription
                failedCount += 1
                errors.append("\(files[i].fileName): \(error.localizedDescription)")
                log.error(error, context: "WebDAV 下载失败: \(files[i].fileName)")
            }
            onTaskUpdate(downloadTasks[i])
            overallProgress = Double(downloadedURLs.count + failedCount + oversizeCount) / Double(total)
        }

        overallProgress = 1.0

        var importResult: ImportResult?
        if !downloadedURLs.isEmpty {
            importResult = await importService.importFromFiles(urls: downloadedURLs) { _ in }

            for url in downloadedURLs {
                try? fileStorage.removeItem(at: url)
            }
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

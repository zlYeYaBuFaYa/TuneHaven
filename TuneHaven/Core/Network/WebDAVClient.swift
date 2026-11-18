import Foundation

actor WebDAVClient: WebDAVClientProtocol {
    struct Configuration: Sendable {
        let baseURL: URL
        let username: String
        let password: String
        let trust: WebDAVTrustPolicy
        let timeoutInterval: TimeInterval

        init(baseURL: URL, username: String, password: String,
             trust: WebDAVTrustPolicy = WebDAVTrustPolicy(trustSelfSigned: false), timeoutInterval: TimeInterval = 30) {
            self.baseURL = baseURL
            self.username = username
            self.password = password
            self.trust = trust
            self.timeoutInterval = timeoutInterval
        }
    }

    private let config: Configuration
    private let session: URLSession
    private let sessionDelegate: WebDAVSessionDelegate
    /// 每个下载单独记录，取消时一并取消；多个下载之间互不影响
    private var downloadTasks: [UUID: Task<URL, Error>] = [:]

    /// `sessionConfiguration` 仅供测试注入 URLProtocol 桩
    init(configuration: Configuration, sessionConfiguration: URLSessionConfiguration = .default) {
        self.config = configuration
        let delegate = WebDAVSessionDelegate(policy: configuration.trust)
        self.sessionDelegate = delegate

        let urlConfig = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .default
        urlConfig.timeoutIntervalForRequest = configuration.timeoutInterval
        self.session = URLSession(configuration: urlConfig, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func testConnection() async throws -> Bool {
        let optionsURL = config.baseURL
        var optionsReq = URLRequest(url: optionsURL)
        optionsReq.httpMethod = "OPTIONS"
        addAuth(to: &optionsReq)

        let (_, optionsResp) = try await data(for: optionsReq)
        guard let http = optionsResp as? HTTPURLResponse else {
            throw AppError.webdavConnectionFailed("无法连接到服务器")
        }

        if http.statusCode == 401 {
            throw AppError.webdavAuthFailed
        }

        let allow = http.value(forHTTPHeaderField: "Allow") ?? ""
        let dav = http.value(forHTTPHeaderField: "DAV") ?? ""
        guard allow.contains("PROPFIND") || !dav.isEmpty else {
            throw AppError.webdavServerNotSupported
        }

        let propfindBody = propfindXML()
        var propReq = URLRequest(url: config.baseURL)
        propReq.httpMethod = "PROPFIND"
        propReq.setValue("0", forHTTPHeaderField: "Depth")
        propReq.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        propReq.httpBody = propfindBody
        addAuth(to: &propReq)

        let (_, propResp) = try await data(for: propReq)
        guard let propHttp = propResp as? HTTPURLResponse else {
            throw AppError.webdavConnectionFailed("PROPFIND 请求失败")
        }

        switch propHttp.statusCode {
        case 200, 207: return true
        case 401: throw AppError.webdavAuthFailed
        case 403: throw AppError.webdavConnectionFailed("无权访问，请检查权限")
        case 404: throw AppError.webdavConnectionFailed("路径不存在，请检查服务器地址")
        default: throw AppError.webdavConnectionFailed("服务器返回 \(propHttp.statusCode)")
        }
    }

    func listDirectory(path: String) async throws -> [WebDAVFile] {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: encodedPath, relativeTo: config.baseURL) else {
            throw AppError.webdavConnectionFailed("无效的目录路径")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = propfindXML()
        addAuth(to: &request)

        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.webdavConnectionFailed("请求失败")
        }

        switch http.statusCode {
        case 207:
            let requestFullPath = url.path
            return try WebDAVXMLParser.parseMultiStatus(data, requestPath: requestFullPath)
        case 401:
            throw AppError.webdavAuthFailed
        case 404:
            throw AppError.webdavConnectionFailed("目录不存在: \(path)")
        default:
            throw AppError.webdavConnectionFailed("服务器返回 \(http.statusCode)")
        }
    }

    func downloadFile(
        remotePath: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let id = UUID()
        let task = Task<URL, Error> {
            try await self.performDownload(remotePath: remotePath, to: destination, progress: progress)
        }
        downloadTasks[id] = task
        defer { downloadTasks[id] = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func fileInfo(path: String) async throws -> (size: Int64, etag: String?) {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: encodedPath, relativeTo: config.baseURL) else {
            throw AppError.webdavConnectionFailed("无效路径")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        addAuth(to: &request)

        let (_, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.webdavConnectionFailed("HEAD 请求失败")
        }

        let size = http.expectedContentLength
        let etag = http.value(forHTTPHeaderField: "ETag")
        return (size, etag)
    }

    func cancelDownload() {
        for task in downloadTasks.values {
            task.cancel()
        }
    }

    func cleanup() {
        cancelDownload()
        session.invalidateAndCancel()
    }

    // MARK: - Private

    /// 不需要 actor 隔离：只读不可变成员。放在 actor 上会让并发下载的字节循环排队执行。
    private nonisolated func performDownload(
        remotePath: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        do {
            return try await streamDownload(remotePath: remotePath, to: destination, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private nonisolated func streamDownload(
        remotePath: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let encodedPath = remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remotePath
        guard let url = URL(string: encodedPath, relativeTo: config.baseURL) else {
            throw AppError.webdavDownloadFailed("无效的文件路径")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(to: &request)

        // 系统直接把响应写入临时文件，进度由任务的字节计数回报，不在 Swift 里逐字节搬运。
        let progressDelegate = DownloadProgressDelegate(progress: progress)
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request, delegate: progressDelegate)
        } catch {
            throw mapTrustError(error)
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppError.webdavDownloadFailed("下载失败 (HTTP \(code))")
        }
        try Task.checkCancellation()

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        let receivedBytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        progress(receivedBytes, http.expectedContentLength)
        return destination
    }

    private nonisolated func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw mapTrustError(error)
        }
    }

    /// 因证书与记住的指纹不符被拒时，URLSession 只报「已取消」，这里换成明确的错误。
    private nonisolated func mapTrustError(_ error: Error) -> Error {
        guard sessionDelegate.rejectedChangedCertificate, let urlError = error as? URLError,
              [.cancelled, .serverCertificateUntrusted, .secureConnectionFailed].contains(urlError.code) else {
            return error
        }
        return AppError.webdavCertificateChanged
    }

    private nonisolated func addAuth(to request: inout URLRequest) {
        guard !config.username.isEmpty else { return }
        let credentials = "\(config.username):\(config.password)"
        if let data = credentials.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }
    }

    private func propfindXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/>
            <d:getcontentlength/>
            <d:getcontenttype/>
            <d:getlastmodified/>
            <d:resourcetype/>
            <d:getetag/>
          </d:prop>
        </d:propfind>
        """
        return Data(xml.utf8)
    }
}

/// 单个下载任务的进度回报。任务创建时开始观察已接收字节数。
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64) -> Void
    private var observation: NSKeyValueObservation?

    init(progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.observe(\.countOfBytesReceived, options: [.new]) { [progress] task, _ in
            progress(task.countOfBytesReceived, task.countOfBytesExpectedToReceive)
        }
    }

    deinit {
        observation?.invalidate()
    }
}

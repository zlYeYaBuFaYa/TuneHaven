import Foundation

actor WebDAVClient {
    struct Configuration {
        let baseURL: URL
        let username: String
        let password: String
        let trustSelfSignedCert: Bool
        let timeoutInterval: TimeInterval

        init(baseURL: URL, username: String, password: String,
             trustSelfSignedCert: Bool = false, timeoutInterval: TimeInterval = 30) {
            self.baseURL = baseURL
            self.username = username
            self.password = password
            self.trustSelfSignedCert = trustSelfSignedCert
            self.timeoutInterval = timeoutInterval
        }
    }

    private let config: Configuration
    private let session: URLSession
    private let sessionDelegate: WebDAVSessionDelegate
    private var downloadTask: Task<URL, Error>?
    private var isCancelled = false

    init(configuration: Configuration) {
        self.config = configuration
        let delegate = WebDAVSessionDelegate(trustSelfSignedCert: configuration.trustSelfSignedCert)
        self.sessionDelegate = delegate

        let urlConfig = URLSessionConfiguration.default
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

        let (_, optionsResp) = try await session.data(for: optionsReq)
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

        let (_, propResp) = try await session.data(for: propReq)
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

        let (data, response) = try await session.data(for: request)
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
        isCancelled = false
        downloadTask?.cancel()

        let task = Task<URL, Error> {
            try await self.performDownload(remotePath: remotePath, to: destination, progress: progress)
        }
        downloadTask = task
        defer { downloadTask = nil }
        return try await task.value
    }

    func fileInfo(path: String) async throws -> (size: Int64, etag: String?) {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: encodedPath, relativeTo: config.baseURL) else {
            throw AppError.webdavConnectionFailed("无效路径")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        addAuth(to: &request)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.webdavConnectionFailed("HEAD 请求失败")
        }

        let size = http.expectedContentLength
        let etag = http.value(forHTTPHeaderField: "ETag")
        return (size, etag)
    }

    func cancelDownload() {
        isCancelled = true
        downloadTask?.cancel()
    }

    func cleanup() {
        downloadTask?.cancel()
        session.invalidateAndCancel()
    }

    // MARK: - Private

    private func performDownload(
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

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppError.webdavDownloadFailed("下载失败 (HTTP \(code))")
        }

        let totalBytes = http.expectedContentLength
        var receivedBytes: Int64 = 0

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let bufferSize = 65536
        var buffer = Data()
        buffer.reserveCapacity(bufferSize)

        for try await byte in asyncBytes {
            if Task.isCancelled { throw AppError.webdavDownloadFailed("下载已取消") }
            if isCancelled { throw AppError.webdavDownloadFailed("下载已取消") }
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= bufferSize {
                handle.write(buffer)
                receivedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(receivedBytes, totalBytes)
            }
        }
        if !buffer.isEmpty {
            handle.write(buffer)
            receivedBytes += Int64(buffer.count)
        }
        progress(receivedBytes, totalBytes)

        return destination
    }

    private func addAuth(to request: inout URLRequest) {
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


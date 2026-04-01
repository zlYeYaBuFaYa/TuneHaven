import Foundation

final class ShareClient: ShareClientProviding {
    private let lock = NSLock()
    private var storedBaseURL: URL?
    private var storedToken: String?

    private let jsonDecoder = JSONDecoder()

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    init() {}

    func connect(to qrContent: String) async throws -> ShareSessionInfo {
        let trimmed = qrContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedURL = URL(string: trimmed),
              let components = URLComponents(url: parsedURL, resolvingAgainstBaseURL: false) else {
            AppLogger.shared.error("[ShareClient] connect: invalid QR URL")
            throw AppError.fileSystemError("无效的分享链接")
        }
        guard let tokenItem = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !tokenItem.isEmpty else {
            AppLogger.shared.error("[ShareClient] connect: missing token")
            throw AppError.fileSystemError("分享链接缺少令牌")
        }
        var baseComponents = URLComponents()
        baseComponents.scheme = components.scheme
        baseComponents.host = components.host
        baseComponents.port = components.port
        guard let baseURL = baseComponents.url else {
            AppLogger.shared.error("[ShareClient] connect: cannot build base URL")
            throw AppError.fileSystemError("无效的分享链接")
        }

        storeCredentials(baseURL: baseURL, token: tokenItem)

        do {
            let info: ShareSessionInfo = try await getJSON(path: "/api/share/info")
            AppLogger.shared.info("[ShareClient] connected — device=\(info.deviceName) songs=\(info.songCount)")
            return info
        } catch {
            clearCredentials()
            throw error
        }
    }

    func fetchSongList() async throws -> [ShareSongSummary] {
        try await getJSON(path: "/api/share/songs")
    }

    func fetchPlaylistList() async throws -> [SharePlaylistSummary] {
        try await getJSON(path: "/api/share/playlists")
    }

    func fetchPlaylistSongs(at index: Int) async throws -> [ShareSongSummary] {
        try await getJSON(path: "/api/share/playlist/\(index)/songs")
    }

    func fetchSongMeta(at index: Int) async throws -> SongExportData {
        try await getJSON(path: "/api/share/song/\(index)/meta")
    }

    func downloadAudio(
        at index: Int,
        to dir: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let (baseURL, token) = try credentials()
        return try await performDownload(
            path: "/api/share/song/\(index)/audio",
            baseURL: baseURL,
            token: token,
            destinationDirectory: dir,
            fallbackFilename: "song_\(index).dat",
            progressHandler: progressHandler
        )
    }

    func downloadCover(at index: Int, to dir: URL) async throws -> URL? {
        let (baseURL, token) = try credentials()
        return try await performOptionalDownload(
            path: "/api/share/song/\(index)/cover",
            baseURL: baseURL,
            token: token,
            destinationDirectory: dir,
            fallbackFilename: "cover_\(index).dat"
        )
    }

    func downloadLyrics(at index: Int, to dir: URL) async throws -> URL? {
        let (baseURL, token) = try credentials()
        return try await performOptionalDownload(
            path: "/api/share/song/\(index)/lyrics",
            baseURL: baseURL,
            token: token,
            destinationDirectory: dir,
            fallbackFilename: "lyrics_\(index).dat"
        )
    }

    func notifyComplete(result: ShareTransferResult) async throws {
        let (baseURL, token) = try credentials()
        let url = try absoluteURL(path: "/api/share/complete", baseURL: baseURL)
        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(result)
        do {
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTP(response: response, path: "/api/share/complete")
        } catch {
            AppLogger.shared.error(error, context: "[ShareClient] notifyComplete")
        }
    }

    func disconnect() {
        lock.lock()
        storedBaseURL = nil
        storedToken = nil
        lock.unlock()
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        AppLogger.shared.info("[ShareClient] disconnected")
    }

    private func storeCredentials(baseURL: URL, token: String) {
        lock.lock()
        storedBaseURL = baseURL
        storedToken = token
        lock.unlock()
    }

    private func clearCredentials() {
        lock.lock()
        storedBaseURL = nil
        storedToken = nil
        lock.unlock()
    }

    private func credentials() throws -> (URL, String) {
        lock.lock()
        defer { lock.unlock() }
        guard let base = storedBaseURL, let token = storedToken else {
            throw AppError.fileSystemError("未连接分享服务器")
        }
        return (base, token)
    }

    private func authorizedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func absoluteURL(path: String, baseURL: URL) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AppError.fileSystemError("无效的请求地址")
        }
        return url
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        let (baseURL, token) = try credentials()
        let url = try absoluteURL(path: path, baseURL: baseURL)
        let request = authorizedRequest(url: url, token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            AppLogger.shared.error(error, context: "[ShareClient] GET \(path)")
            throw mapURLError(error)
        }
        try validateHTTP(response: response, path: path)
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            AppLogger.shared.error("[ShareClient] decode failed for \(path): \(error.localizedDescription)")
            throw AppError.fileSystemError("数据解析失败")
        }
    }

    private func validateHTTP(response: URLResponse, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppError.fileSystemError("无效的响应")
        }
        guard (200...299).contains(http.statusCode) else {
            AppLogger.shared.error("[ShareClient] HTTP \(http.statusCode) for \(path)")
            throw AppError.fileSystemError("请求失败 (\(http.statusCode))")
        }
    }

    private var localNetworkSettingsPath: String {
        if #available(iOS 18, *) {
            return "设置 → App → TuneHaven → 本地网络"
        } else {
            return "设置 → TuneHaven → 本地网络"
        }
    }

    private func mapURLError(_ error: Error) -> AppError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
                   underlying.domain == "kCFErrorDomainCFNetwork" || underlying.localizedDescription.contains("local network") {
                    return AppError.fileSystemError("无法连接到发送端设备，请确认已在「\(localNetworkSettingsPath)」中允许访问，并确保两台设备在同一 WiFi 下")
                }
                return AppError.fileSystemError("无法连接到发送端设备，请确保两台设备在同一 WiFi 网络下，并在「\(localNetworkSettingsPath)」中检查权限是否已开启")
            case NSURLErrorTimedOut:
                return AppError.fileSystemError("连接超时，请确保两台设备在同一 WiFi 网络下")
            default:
                break
            }
        }
        return AppError.fileSystemError(error.localizedDescription)
    }

    private func performDownload(
        path: String,
        baseURL: URL,
        token: String,
        destinationDirectory: URL,
        fallbackFilename: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let url = try absoluteURL(path: path, baseURL: baseURL)
        let request = authorizedRequest(url: url, token: token)
        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await urlSession.download(for: request)
        } catch {
            AppLogger.shared.error(error, context: "[ShareClient] download \(path)")
            throw mapURLError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: tempURL)
            throw AppError.fileSystemError("无效的响应")
        }
        guard (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            AppLogger.shared.error("[ShareClient] download HTTP \(http.statusCode) for \(path)")
            throw AppError.fileSystemError("下载失败 (\(http.statusCode))")
        }
        let filename = suggestedFilename(from: http, fallback: fallbackFilename)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destURL = destinationDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        progressHandler(1.0)
        return destURL
    }

    private func performOptionalDownload(
        path: String,
        baseURL: URL,
        token: String,
        destinationDirectory: URL,
        fallbackFilename: String
    ) async throws -> URL? {
        let url = try absoluteURL(path: path, baseURL: baseURL)
        let request = authorizedRequest(url: url, token: token)
        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await urlSession.download(for: request)
        } catch {
            AppLogger.shared.error(error, context: "[ShareClient] download \(path)")
            throw mapURLError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: tempURL)
            throw AppError.fileSystemError("无效的响应")
        }
        if http.statusCode == 404 {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        guard (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            AppLogger.shared.error("[ShareClient] download HTTP \(http.statusCode) for \(path)")
            throw AppError.fileSystemError("下载失败 (\(http.statusCode))")
        }
        let filename = suggestedFilename(from: http, fallback: fallbackFilename)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destURL = destinationDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    private func suggestedFilename(from response: HTTPURLResponse, fallback: String) -> String {
        if let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           let parsed = parseFilename(from: disposition) {
            let last = (parsed as NSString).lastPathComponent
            if !last.isEmpty { return last }
        }
        return fallback
    }

    private func parseFilename(from contentDisposition: String) -> String? {
        if let starRange = contentDisposition.range(of: "filename*=", options: .caseInsensitive) {
            let rest = String(contentDisposition[starRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let q2 = rest.range(of: "''") {
                var value = String(rest[q2.upperBound...])
                value = value.split(separator: ";").first.map(String.init) ?? value
                value = value.trimmingCharacters(in: .whitespaces)
                if let decoded = value.removingPercentEncoding { return decoded }
                return value
            }
        }
        if let fnRange = contentDisposition.range(of: "filename=", options: .caseInsensitive) {
            var rest = String(contentDisposition[fnRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("\"") {
                rest.removeFirst()
                if let end = rest.firstIndex(of: "\"") {
                    return String(rest[..<end])
                }
            } else {
                let segment = rest.split(separator: ";").first.map(String.init) ?? rest
                return segment.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

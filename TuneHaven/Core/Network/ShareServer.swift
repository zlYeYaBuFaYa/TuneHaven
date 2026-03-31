import Darwin
import Foundation
import Network

@MainActor
final class ShareServer: ObservableObject, ShareServerProviding {
    @Published private(set) var isRunning = false
    @Published private(set) var serverAddress: String?
    @Published private(set) var connectedDevice: String?
    private let log = AppLogger.shared

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let port: UInt16 = 8090
    private let sessionToken = UUID().uuidString
    private let streamChunkSize = 1_048_576 // 1 MB

    var dataSource: ShareDataSource?
    var onAudioFileServed: ((Int) -> Void)?
    var onDeviceConnected: ((String) -> Void)?
    var onTransferCompleted: ((ShareTransferResult) -> Void)?
    var onReceiverDisconnected: (() -> Void)?

    private var hasReceivedComplete = false
    private var inactivityTimer: Timer?
    private let inactivityTimeout: TimeInterval = 30

    var qrCodeContent: String? {
        guard let addr = serverAddress else { return nil }
        return "http://\(addr):\(port)?token=\(sessionToken)"
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }
        log.info("[ShareServer] 启动")

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AppError.wifiServerStartFailed
        }
        let newListener = try NWListener(using: params, on: nwPort)
        self.listener = newListener

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.serverAddress = self?.resolveLocalIP()
                        if !resumed {
                            resumed = true
                            continuation.resume()
                        }
                    case .failed(let error):
                        self?.isRunning = false
                        if !resumed {
                            resumed = true
                            continuation.resume(throwing: error)
                        }
                    case .cancelled:
                        self?.isRunning = false
                        if !resumed {
                            resumed = true
                            continuation.resume(throwing: AppError.wifiServerStartFailed)
                        }
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(conn)
                }
            }

            newListener.start(queue: .main)
        }

        guard serverAddress != nil else {
            stop()
            throw AppError.fileSystemError("无法获取服务器地址")
        }
    }

    func stop() {
        log.info("[ShareServer] 停止")
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        listener?.cancel()
        listener = nil
        activeConnection?.cancel()
        activeConnection = nil
        isRunning = false
        serverAddress = nil
        connectedDevice = nil
        hasReceivedComplete = false
    }

    // MARK: - Connection

    private func handleNewConnection(_ connection: NWConnection) {
        if let active = activeConnection {
            active.stateUpdateHandler = nil
            active.cancel()
        }
        activeConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.activeConnection === connection else { return }
                if case .failed = state { self.activeConnection = nil }
                if case .cancelled = state { self.activeConnection = nil }
            }
        }

        receiveRequest(connection: connection)
        connection.start(queue: .main)
    }

    private func receiveRequest(connection: NWConnection) {
        var buffer = Data()

        func readLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { connection.cancel(); return }
                if let data, !data.isEmpty { buffer.append(data) }
                Task { @MainActor [weak self] in
                    guard let self else { connection.cancel(); return }
                    if isComplete || error != nil {
                        if !buffer.isEmpty { self.routeRequest(buffer, connection: connection) }
                        return
                    }
                    guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                        if buffer.count > 16_384 {
                            self.sendResponse(connection: connection, status: 400, body: Data(#"{"error":"请求头过大"}"#.utf8))
                        } else {
                            readLoop()
                        }
                        return
                    }
                    let contentLength = self.parseContentLength(from: buffer[buffer.startIndex..<headerEnd.lowerBound])
                    let bodyReceived = buffer.endIndex - headerEnd.upperBound
                    if bodyReceived < contentLength {
                        readLoop()
                    } else {
                        self.routeRequest(buffer, connection: connection)
                    }
                }
            }
        }

        readLoop()
    }

    private func parseContentLength(from headerData: Data) -> Int {
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return 0 }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let value = extractHeader(from: lines, key: "Content-Length"),
              let length = Int(value), length > 0 else { return 0 }
        return length
    }

    // MARK: - Routing

    private func routeRequest(_ data: Data, connection: NWConnection) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let headerStr = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: Data(#"{"error":"无法解析请求"}"#.utf8))
            return
        }

        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: Data(#"{"error":"请求行缺失"}"#.utf8))
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: Data(#"{"error":"请求格式错误"}"#.utf8))
            return
        }

        let method = String(parts[0])
        let rawPath = String(parts[1])
        let path = rawPath.components(separatedBy: "?").first ?? rawPath

        let token = extractHeader(from: lines, key: "Authorization")?
            .replacingOccurrences(of: "Bearer ", with: "")
        if token != sessionToken {
            sendResponse(connection: connection, status: 401, body: Data(#"{"error":"未授权"}"#.utf8))
            return
        }

        resetInactivityTimer()

        if method == "POST" && path == "/api/share/complete" {
            let bodyData = data[headerEnd.upperBound...]
            handleComplete(body: Data(bodyData), connection: connection)
            return
        }

        guard method == "GET" else {
            sendResponse(connection: connection, status: 405, body: Data(#"{"error":"方法不允许"}"#.utf8))
            return
        }

        switch path {
        case "/api/share/info":
            handleInfo(connection: connection)
        case "/api/share/songs":
            handleSongList(connection: connection)
        case "/api/share/playlists":
            handlePlaylistList(connection: connection)
        default:
            if let match = matchPath("/api/share/playlist/(\\d+)/songs", path: path) {
                handlePlaylistSongs(index: match, connection: connection)
            } else if let match = matchPath("/api/share/song/(\\d+)/audio", path: path) {
                handleSongFile(index: match, type: .audio, connection: connection)
            } else if let match = matchPath("/api/share/song/(\\d+)/cover", path: path) {
                handleSongFile(index: match, type: .cover, connection: connection)
            } else if let match = matchPath("/api/share/song/(\\d+)/lyrics", path: path) {
                handleSongFile(index: match, type: .lyrics, connection: connection)
            } else if let match = matchPath("/api/share/song/(\\d+)/meta", path: path) {
                handleSongMeta(index: match, connection: connection)
            } else {
                sendResponse(connection: connection, status: 404, body: Data(#"{"error":"未找到"}"#.utf8))
            }
        }
    }

    // MARK: - Handlers

    private func handleInfo(connection: NWConnection) {
        if connectedDevice == nil, let endpoint = activeConnection?.endpoint,
           case let .hostPort(host, _) = endpoint {
            let deviceId = "\(host)"
            connectedDevice = deviceId
            onDeviceConnected?(deviceId)
        }
        guard let info = dataSource?.sessionInfo() else {
            sendResponse(connection: connection, status: 500, body: Data(#"{"error":"数据源未就绪"}"#.utf8))
            return
        }
        let enriched = ShareSessionInfo(
            deviceName: info.deviceName,
            sessionToken: sessionToken,
            songCount: info.songCount,
            playlistCount: info.playlistCount,
            totalSize: info.totalSize
        )
        sendJSON(connection: connection, value: enriched)
    }

    private func handleSongList(connection: NWConnection) {
        guard let list = dataSource?.songSummaries() else {
            sendResponse(connection: connection, status: 500, body: Data(#"{"error":"数据源未就绪"}"#.utf8))
            return
        }
        sendJSON(connection: connection, value: list)
    }

    private func handlePlaylistList(connection: NWConnection) {
        guard let list = dataSource?.playlistSummaries() else {
            sendResponse(connection: connection, status: 500, body: Data(#"{"error":"数据源未就绪"}"#.utf8))
            return
        }
        sendJSON(connection: connection, value: list)
    }

    private func handlePlaylistSongs(index: Int, connection: NWConnection) {
        guard let songs = dataSource?.playlistSongs(at: index) else {
            sendResponse(connection: connection, status: 404, body: Data(#"{"error":"歌单不存在"}"#.utf8))
            return
        }
        sendJSON(connection: connection, value: songs)
    }

    private func handleSongMeta(index: Int, connection: NWConnection) {
        guard let meta = dataSource?.songExportData(at: index) else {
            sendResponse(connection: connection, status: 404, body: Data(#"{"error":"歌曲不存在"}"#.utf8))
            return
        }
        sendJSON(connection: connection, value: meta)
    }

    private func handleComplete(body: Data, connection: NWConnection) {
        guard let result = try? JSONDecoder().decode(ShareTransferResult.self, from: body) else {
            sendResponse(connection: connection, status: 400, body: Data(#"{"error":"无法解析完成通知"}"#.utf8))
            return
        }
        hasReceivedComplete = true
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        log.info("[ShareServer] 收到接收端完成通知: 新增=\(result.songsReceived) 跳过=\(result.songsSkipped)")
        onTransferCompleted?(result)
        sendResponse(connection: connection, status: 200, body: Data(#"{"ok":true}"#.utf8))
    }

    private enum FileType { case audio, cover, lyrics }

    private func handleSongFile(index: Int, type: FileType, connection: NWConnection) {
        let url: URL?
        switch type {
        case .audio: url = dataSource?.audioFileURL(at: index)
        case .cover: url = dataSource?.coverFileURL(at: index)
        case .lyrics: url = dataSource?.lyricsFileURL(at: index)
        }

        guard let fileURL = url else {
            sendResponse(connection: connection, status: 404, body: Data(#"{"error":"文件不存在"}"#.utf8))
            return
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attrs[.size] as? UInt64 else {
            sendResponse(connection: connection, status: 500, body: Data(#"{"error":"无法读取文件信息"}"#.utf8))
            return
        }

        let fileName = fileURL.lastPathComponent
        let mimeType = mimeForExtension(fileURL.pathExtension)
        let disposition = contentDisposition(for: fileName)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mimeType)\r\nContent-Length: \(fileSize)\r\n\(disposition)\r\nConnection: close\r\n\r\n"

        let onComplete: (() -> Void)? = (type == .audio) ? { [weak self] in
            Task { @MainActor in self?.onAudioFileServed?(index) }
        } : nil

        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            Task { @MainActor in
                self?.streamFile(url: fileURL, size: fileSize, connection: connection, onComplete: onComplete)
            }
        })
    }

    private func streamFile(url: URL, size: UInt64, connection: NWConnection, onComplete: (() -> Void)? = nil) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            connection.cancel()
            return
        }

        var remaining = size
        func sendChunk() {
            let chunkSize = min(UInt64(streamChunkSize), remaining)
            let chunk = handle.readData(ofLength: Int(chunkSize))
            guard !chunk.isEmpty else {
                try? handle.close()
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                return
            }
            remaining -= UInt64(chunk.count)
            let isLast = remaining == 0
            connection.send(content: chunk, isComplete: isLast, completion: .contentProcessed { error in
                if error != nil || isLast {
                    try? handle.close()
                    if isLast {
                        onComplete?()
                        connection.cancel()
                    }
                } else {
                    Task { @MainActor in
                        sendChunk()
                    }
                }
            })
        }

        sendChunk()
    }

    // MARK: - Helpers

    private func sendJSON<T: Encodable>(connection: NWConnection, value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else {
            sendResponse(connection: connection, status: 500, body: Data(#"{"error":"序列化失败"}"#.utf8))
            return
        }
        sendResponse(connection: connection, status: 200, body: data, contentType: "application/json; charset=utf-8")
    }

    private func sendResponse(connection: NWConnection, status: Int, body: Data, contentType: String = "application/json") {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Error"
        }

        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func extractHeader(from lines: [String], key: String) -> String? {
        let prefix = key.lowercased() + ":"
        for line in lines {
            if line.lowercased().hasPrefix(prefix) {
                return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static let routePatterns: [(NSRegularExpression, String)] = {
        let patterns = [
            "/api/share/playlist/(\\d+)/songs",
            "/api/share/song/(\\d+)/audio",
            "/api/share/song/(\\d+)/cover",
            "/api/share/song/(\\d+)/lyrics",
            "/api/share/song/(\\d+)/meta",
        ]
        return patterns.compactMap { p in
            guard let r = try? NSRegularExpression(pattern: "^\(p)$") else { return nil }
            return (r, p)
        }
    }()

    private func matchPath(_ pattern: String, path: String) -> Int? {
        guard let entry = Self.routePatterns.first(where: { $0.1 == pattern }) else { return nil }
        let regex = entry.0
        guard let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: path),
              let index = Int(path[range]) else { return nil }
        return index
    }

    private func contentDisposition(for filename: String) -> String {
        let ascii = filename.unicodeScalars.allSatisfy { $0.isASCII }
        if ascii {
            return "Content-Disposition: attachment; filename=\"\(filename)\""
        }
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        return "Content-Disposition: attachment; filename*=utf-8''\(encoded)"
    }

    private func mimeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/mp4"
        case "flac": return "audio/flac"
        case "wav": return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "caf": return "audio/x-caf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "lrc", "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Inactivity Timeout

    private func resetInactivityTimer() {
        guard connectedDevice != nil, !hasReceivedComplete else { return }
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.hasReceivedComplete, self.connectedDevice != nil else { return }
                self.log.info("[ShareServer] 接收端无活动超时 (\(self.inactivityTimeout)s)")
                self.onReceiverDisconnected?()
            }
        }
    }

    /// WiFi 通常为 en0，个人热点桥接为 bridge100 / ap1 等
    private static let preferredInterfaces = ["en0", "en1", "bridge100", "ap1"]

    private func resolveLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [String: String] = [:]
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard Self.preferredInterfaces.contains(name) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(sa.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            candidates[name] = String(cString: hostname)
        }

        for iface in Self.preferredInterfaces {
            if let ip = candidates[iface] { return ip }
        }
        return nil
    }
}

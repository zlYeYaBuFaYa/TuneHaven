import Darwin
import Foundation
import Network

/// 密码开启后的上传许可。token 只活在内存里，停止服务或更换密码时作废。
struct WiFiTransferSession: Equatable {
    var passwordEnabled = false
    private(set) var uploadToken: String?

    mutating func issueUploadToken() -> String {
        let token = UUID().uuidString
        uploadToken = token
        return token
    }

    mutating func invalidateUploadToken() {
        uploadToken = nil
    }

    func allowsUpload(authorizationHeader: String?) -> Bool {
        guard passwordEnabled else { return true }
        guard let uploadToken, !uploadToken.isEmpty else { return false }
        guard let header = authorizationHeader?.trimmingCharacters(in: .whitespacesAndNewlines),
              header.hasPrefix("Bearer ") else { return false }
        let presented = String(header.dropFirst("Bearer ".count))
        return !presented.isEmpty && presented == uploadToken
    }
}

@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var serverAddress: String?
    @Published private(set) var password: String?
    @Published private(set) var connectionState: WiFiConnectionState = .idle
    @Published private(set) var transferProgress: WiFiTransferProgress?
    @Published private(set) var securityAlert: WiFiSecurityAlert?
    private let log = AppLogger.shared

    var onFileReceived: (@MainActor (String, URL) -> Void)?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var session = WiFiTransferSession()
    private var authAttempts: [String: (attempts: Int, cooldownUntil: Date?)] = [:]
    private let port: UInt16

    /// `port` 仅供测试换用不同端口，避免上一个监听还没释放
    init(port: UInt16 = 8080) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start(passwordEnabled: Bool) throws {
        guard !isRunning else { return }
        log.info("WiFi 传输服务启动")
        session.passwordEnabled = passwordEnabled
        session.invalidateUploadToken()
        if passwordEnabled && password == nil { password = generateRandomPassword() }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AppError.wifiServerStartFailed
        }
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.serverAddress = self?.resolveLocalIP()
                case .failed, .cancelled:
                    self?.isRunning = false
                default: break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.handleNewConnection(connection)
            }
        }

        listener.start(queue: .main)
    }

    func stop() {
        log.info("WiFi 传输服务停止")
        listener?.cancel()
        listener = nil
        activeConnection?.cancel()
        activeConnection = nil
        isRunning = false
        connectionState = .idle
        serverAddress = nil
        session.invalidateUploadToken()
        authAttempts.removeAll()
    }

    func regeneratePassword() -> String {
        let pwd = generateRandomPassword()
        password = pwd
        session.invalidateUploadToken()
        return pwd
    }

    func setCustomPassword(_ pwd: String) throws {
        guard pwd.count >= 6, pwd.allSatisfy({ $0.isNumber }) else {
            throw AppError.wifiPasswordWrong
        }
        password = pwd
        session.invalidateUploadToken()
    }

    /// 启动时调用：清掉流式上传的中间文件，以及上次进程没来得及导入的上传文件。
    nonisolated static func cleanupTempFiles() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        let contents = (try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix("wifi_upload_") {
            try? fm.removeItem(at: url)
        }
        let uploads = (try? fm.contentsOfDirectory(
            at: SandboxPathManager.wifiUploadURL, includingPropertiesForKeys: nil)) ?? []
        for url in uploads {
            try? fm.removeItem(at: url)
        }
    }

    /// 上传文件的落盘位置。加 UUID 前缀，同名文件排队导入时不会互相覆盖。
    nonisolated static func uploadDestination(for rawFilename: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(UUID().uuidString)-\(safeFilename(rawFilename))")
    }

    /// 只取最后一段路径；空串、`.`、`..` 退回 `uploaded_file`。
    nonisolated static func safeFilename(_ rawFilename: String) -> String {
        let name = (rawFilename as NSString).lastPathComponent
        return (name.isEmpty || name == "." || name == ".." || name == "/") ? "uploaded_file" : name
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        guard case let .hostPort(host, _) = connection.endpoint else {
            connection.cancel()
            return
        }
        let ip = "\(host)"

        if let active = activeConnection {
            if case .transferring = connectionState {
                securityAlert = .newDeviceWhileTransferring(ip: ip)
                connection.cancel()
                return
            }
            active.cancel()
        }

        activeConnection = connection
        connectionState = .connected(ip: ip)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                // 每次响应后都会关闭连接，旧连接的关闭不能把新连接的状态改回空闲
                guard let self, self.activeConnection === connection else { return }
                if case .failed = state { self.connectionState = .idle }
                if case .cancelled = state { self.connectionState = .idle }
            }
        }

        receiveHTTPRequest(connection: connection, ip: ip)
        connection.start(queue: .main)
    }

    // MARK: - Two-Phase HTTP Receive

    private func receiveHTTPRequest(connection: NWConnection, ip: String) {
        var headerData = Data()

        func headerReadLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { connection.cancel(); return }
                if let data, !data.isEmpty { headerData.append(data) }
                Task { @MainActor [weak self] in
                    guard let self else { connection.cancel(); return }
                    if isComplete || error != nil {
                        if !headerData.isEmpty {
                            self.handleHTTPData(headerData, connection: connection, ip: ip)
                        }
                        self.connectionState = .idle
                        return
                    }

                    let headerEndMarker = Data("\r\n\r\n".utf8)
                    if let headerEndRange = headerData.range(of: headerEndMarker) {
                        let headers = headerData[headerData.startIndex..<headerEndRange.upperBound]
                        let overflow = headerData[headerEndRange.upperBound...]

                        if self.isUploadRequest(headers) {
                            let headerBytes = Data(headers)
                            guard self.isSameOriginRequest(headerBytes) else {
                                self.sendJSON(connection: connection, status: 403, body: #"{"error":"禁止跨站请求"}"#)
                                self.connectionState = .idle
                                return
                            }
                            guard self.allowsUpload(headers: headerBytes) else {
                                self.sendJSON(connection: connection, status: 401, body: #"{"error":"未授权"}"#)
                                self.connectionState = .idle
                                return
                            }
                            guard let ctx = self.beginStreamingUpload(headers: headerBytes, ip: ip) else {
                                self.finishSmallRequest(headerData: headerData, connection: connection, ip: ip)
                                return
                            }
                            if !overflow.isEmpty {
                                ctx.fileHandle.write(Data(overflow))
                                ctx.bytesReceived = overflow.count
                                self.updateTransferProgress(ctx)
                            }
                            // 小文件可能和请求头同一包到达，已收齐就不再等后续数据
                            if ctx.bytesReceived >= ctx.contentLength {
                                ctx.fileHandle.closeFile()
                                self.processUploadedTempFile(context: ctx, connection: connection)
                            } else {
                                self.bodyReadLoop(context: ctx, connection: connection)
                            }
                        } else {
                            self.finishSmallRequest(headerData: headerData, connection: connection, ip: ip)
                        }
                    } else if headerData.count > 16_384 {
                        self.sendJSON(connection: connection, status: 400, body: #"{"error":"请求头过大"}"#)
                    } else {
                        headerReadLoop()
                    }
                }
            }
        }

        headerReadLoop()
    }

    private func bodyReadLoop(context: StreamingUploadContext, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                if let data, !data.isEmpty {
                    context.fileHandle.write(data)
                    context.bytesReceived += data.count
                    self.updateTransferProgress(context)
                }
                if error != nil {
                    context.fileHandle.closeFile()
                    try? FileManager.default.removeItem(at: context.tempFileURL)
                    self.transferProgress = nil
                    self.connectionState = .idle
                    return
                }
                if isComplete || context.bytesReceived >= context.contentLength {
                    context.fileHandle.closeFile()
                    self.processUploadedTempFile(context: context, connection: connection)
                } else {
                    self.bodyReadLoop(context: context, connection: connection)
                }
            }
        }
    }

    // MARK: - Small Request Handling (GET, POST /auth)

    private func finishSmallRequest(headerData: Data, connection: NWConnection, ip: String) {
        if isCompleteHTTPRequest(headerData) {
            handleHTTPData(headerData, connection: connection, ip: ip)
        } else {
            receiveSmallBody(existingData: headerData, connection: connection, ip: ip)
        }
    }

    private func receiveSmallBody(existingData: Data, connection: NWConnection, ip: String) {
        var data = existingData
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if let chunk { data.append(chunk) }
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                if isComplete || error != nil || self.isCompleteHTTPRequest(data) {
                    self.handleHTTPData(data, connection: connection, ip: ip)
                    if isComplete || error != nil { self.connectionState = .idle }
                } else if data.count > 1_048_576 {
                    self.sendJSON(connection: connection, status: 413, body: #"{"error":"请求体过大"}"#)
                } else {
                    self.receiveSmallBody(existingData: data, connection: connection, ip: ip)
                }
            }
        }
    }

    // MARK: - Streaming Upload Helpers

    private func isUploadRequest(_ headerData: Data) -> Bool {
        guard let str = String(data: headerData, encoding: .utf8) else { return false }
        return str.hasPrefix("POST") && str.contains("/upload")
    }

    private func beginStreamingUpload(headers: Data, ip: String) -> StreamingUploadContext? {
        guard let contentLengthStr = extractHeader(from: headers, key: "Content-Length"),
              let contentLength = Int(contentLengthStr),
              let contentType = extractHeader(from: headers, key: "Content-Type"),
              let boundary = extractBoundary(from: contentType) else { return nil }
        guard contentLength <= Self.maxUploadBytes else {
            log.error("上传文件过大: \(contentLength) bytes，上限 \(Self.maxUploadBytes)")
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifi_upload_\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: tempURL.path) else { return nil }

        connectionState = .transferring(ip: ip)
        return StreamingUploadContext(
            contentLength: contentLength,
            boundary: boundary,
            tempFileURL: tempURL,
            fileHandle: handle)
    }

    private func processUploadedTempFile(context: StreamingUploadContext, connection: NWConnection) {
        defer {
            try? FileManager.default.removeItem(at: context.tempFileURL)
            transferProgress = nil
        }

        // TODO: 当前实现将流式写入的临时文件全量回读到内存进行 multipart 解析，
        // 大文件场景下内存开销较高。未来可改为流式 multipart 解析以降低峰值内存占用。
        guard let bodyData = try? Data(contentsOf: context.tempFileURL, options: .mappedIfSafe) else {
            sendJSON(connection: connection, status: 500, body: #"{"error":"临时文件读取失败"}"#)
            connectionState = .idle
            return
        }
        parseMultipart(bodyData: bodyData, boundary: context.boundary, connection: connection)
    }

    private func updateTransferProgress(_ context: StreamingUploadContext) {
        let elapsed = Date().timeIntervalSince(context.startTime)
        let speed = elapsed > 0 ? Double(context.bytesReceived) / elapsed : 0
        transferProgress = WiFiTransferProgress(
            fileName: "",
            bytesReceived: Int64(context.bytesReceived),
            totalBytes: Int64(context.contentLength),
            speed: speed
        )
    }

    // MARK: - HTTP Request Completeness

    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8),
              let firstLine = str.components(separatedBy: "\r\n").first else { return true }
        if firstLine.contains("GET ") { return true }
        guard firstLine.contains("POST ") else { return true }
        guard let contentLengthStr = extractHeader(from: data, key: "Content-Length"),
              let contentLength = Int(contentLengthStr) else { return true }
        guard let bodyData = extractBodyData(from: data) else { return false }
        return bodyData.count >= contentLength
    }

    // MARK: - HTTP Routing

    private func handleHTTPData(_ data: Data, connection: NWConnection, ip: String) {
        guard let request = String(data: data, encoding: .utf8) else { return }
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        if firstLine.hasPrefix("POST "), !isSameOriginRequest(data) {
            sendJSON(connection: connection, status: 403, body: #"{"error":"禁止跨站请求"}"#)
            return
        }

        if firstLine.contains("GET / ") {
            sendHTML(connection: connection)
        } else if firstLine.contains("POST /auth") {
            handleAuth(data: data, connection: connection, ip: ip)
        } else if firstLine.contains("POST /upload") {
            handleUpload(data: data, connection: connection)
        } else if firstLine.contains("GET /status") {
            sendStatus(connection: connection)
        } else if firstLine.contains("GET /heartbeat") {
            sendJSON(connection: connection, status: 200, body: #"{"alive":true}"#)
        } else {
            send404(connection: connection)
        }
    }

    // MARK: - Auth

    private func handleAuth(data: Data, connection: NWConnection, ip: String) {
        var record = authAttempts[ip] ?? (attempts: 0, cooldownUntil: nil)

        if let cooldown = record.cooldownUntil, Date() < cooldown {
            sendJSON(connection: connection, status: 429, body: #"{"error":"请稍后再试"}"#)
            return
        }

        if let cooldown = record.cooldownUntil, Date() >= cooldown {
            record = (attempts: 0, cooldownUntil: nil)
            authAttempts[ip] = record
        }

        guard let body = extractBody(from: data),
              let pwd = extractField(body, key: "password") else {
            sendJSON(connection: connection, status: 400, body: #"{"error":"缺少密码"}"#)
            return
        }

        if session.passwordEnabled && pwd != (password ?? "") {
            record.attempts += 1
            if record.attempts >= 5 {
                record.cooldownUntil = Date().addingTimeInterval(30)
                securityAlert = .bruteForceDetected(ip: ip, attemptCount: record.attempts)
                authAttempts[ip] = record
                sendJSON(connection: connection, status: 429, body: #"{"error":"密码错误次数过多，请等待30秒"}"#)
            } else {
                authAttempts[ip] = record
                sendJSON(connection: connection, status: 401, body: #"{"error":"密码错误"}"#)
            }
            return
        }

        authAttempts[ip] = (attempts: 0, cooldownUntil: nil)
        let token = session.issueUploadToken()
        sendJSON(connection: connection, status: 200, body: #"{"success":true,"token":"\#(token)"}"#)
    }

    // MARK: - Upload (fallback for small in-memory requests)

    private func handleUpload(data: Data, connection: NWConnection) {
        guard allowsUpload(headers: data) else {
            sendJSON(connection: connection, status: 401, body: #"{"error":"未授权"}"#)
            return
        }

        if let clStr = extractHeader(from: data, key: "Content-Length"),
           let cl = Int(clStr), cl > Self.maxUploadBytes {
            sendJSON(connection: connection, status: 413, body: #"{"error":"文件过大，超过上传限制"}"#)
            return
        }

        guard let contentType = extractHeader(from: data, key: "Content-Type"),
              contentType.contains("multipart/form-data") else {
            sendJSON(connection: connection, status: 400, body: #"{"error":"需要multipart/form-data"}"#)
            return
        }

        if let boundary = extractBoundary(from: contentType),
           let bodyData = extractBodyData(from: data) {
            parseMultipart(bodyData: bodyData, boundary: boundary, connection: connection)
        } else {
            sendJSON(connection: connection, status: 400, body: #"{"error":"解析失败"}"#)
        }
    }

    // MARK: - Multipart Parsing

    private func parseMultipart(bodyData: Data, boundary: String, connection: NWConnection) {
        guard let boundaryData = ("--" + boundary).data(using: .utf8),
              let headerSeparator = "\r\n\r\n".data(using: .utf8) else {
            sendJSON(connection: connection, status: 500, body: #"{"error":"编码失败"}"#)
            return
        }
        let parts = bodyData.components(separatedBy: boundaryData)
        var savedFiles: [(name: String, url: URL)] = []

        for part in parts {
            guard let headerEnd = part.range(of: headerSeparator) else { continue }
            let headerData = part[part.startIndex..<headerEnd.lowerBound]
            var fileData = part[headerEnd.upperBound...]
            if fileData.count >= 2 && fileData.suffix(2) == Data([0x0D, 0x0A]) {
                fileData = fileData.dropLast(2)
            }
            guard let headerStr = String(data: headerData, encoding: .utf8),
                  headerStr.contains("filename=") else { continue }

            let rawFilename = extractFilenameFromHeader(headerStr) ?? "uploaded_file"
            let destURL = Self.uploadDestination(for: rawFilename, in: SandboxPathManager.wifiUploadURL)
            let filename = Self.safeFilename(rawFilename)
            do {
                try fileData.write(to: destURL)
                savedFiles.append((name: filename, url: destURL))
            } catch {
                log.error(error, context: "WiFi上传文件写入失败: \(filename)")
            }
        }

        connectionState = .idle
        if savedFiles.isEmpty {
            sendJSON(connection: connection, status: 400, body: #"{"error":"未找到文件"}"#)
        } else {
            sendJSON(connection: connection, status: 200, body: #"{"success":true}"#)
            for file in savedFiles {
                onFileReceived?(file.name, file.url)
            }
        }
    }

    // MARK: - HTTP Response

    private func sendHTML(connection: NWConnection) {
        let html = WiFiTransferHTML.page(address: serverAddress ?? "", passwordRequired: session.passwordEnabled)
        guard let bodyData = html.data(using: .utf8) else { return }
        let response = buildHTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: bodyData)
        sendAndClose(response, on: connection)
    }

    private func sendJSON(connection: NWConnection, status: Int, body: String) {
        guard let bodyData = body.data(using: .utf8) else { return }
        let response = buildHTTPResponse(status: status, contentType: "application/json", body: bodyData)
        sendAndClose(response, on: connection)
    }

    /// 响应头声明了 `Connection: close`，发完即关闭，出错返回后也不会留着连接。
    private func sendAndClose(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendStatus(connection: NWConnection) {
        let json = #"{"isRunning":true}"#
        sendJSON(connection: connection, status: 200, body: json)
    }

    private func send404(connection: NWConnection) {
        sendJSON(connection: connection, status: 404, body: #"{"error":"not found"}"#)
    }

    private static let maxUploadBytes = 500 * 1024 * 1024

    private func buildHTTPResponse(status: Int, contentType: String, body: Data) -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        case 429: statusText = "Too Many Requests"
        case 500: statusText = "Internal Server Error"
        default: statusText = "OK"
        }
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        guard var response = header.data(using: .utf8) else { return body }
        response.append(body)
        return response
    }

    // MARK: - Network Utilities

    private func resolveLocalIP() -> String? {
        var wifiAddress: String?
        var fallbackAddress: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            // 部分接口没有地址（ifa_addr 为 NULL），直接解引用会崩溃
            if let addr = current.pointee.ifa_addr,
               flags & (IFF_UP | IFF_RUNNING) != 0 && flags & IFF_LOOPBACK == 0 {
                let family = addr.pointee.sa_family
                if family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        let name = String(cString: current.pointee.ifa_name)
                        if name == "en0" {
                            wifiAddress = ip
                        } else if fallbackAddress == nil {
                            fallbackAddress = ip
                        }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return (wifiAddress ?? fallbackAddress).map { "http://\($0):\(port)" }
    }

    private func generateRandomPassword() -> String {
        (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
    }

    // MARK: - HTTP Parsing Utilities

    private func extractBody(from data: Data) -> String? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let parts = str.components(separatedBy: "\r\n\r\n")
        return parts.count > 1 ? parts[1...].joined(separator: "\r\n\r\n") : nil
    }

    private func extractBodyData(from data: Data) -> Data? {
        guard let marker = "\r\n\r\n".data(using: .utf8),
              let range = data.range(of: marker) else { return nil }
        return data[range.upperBound...]
    }

    private func extractField(_ body: String, key: String) -> String? {
        let pairs = body.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 && kv[0] == key {
                return kv[1].removingPercentEncoding
            }
        }
        if let jsonData = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
            return json[key]
        }
        return nil
    }

    private func isSameOriginRequest(_ headers: Data) -> Bool {
        Self.isSameOrigin(origin: extractHeader(from: headers, key: "Origin"),
                          host: extractHeader(from: headers, key: "Host"))
    }

    /// 浏览器的跨站 POST 会带上别的 `Origin`；multipart 表单属于简单请求，不经预检就会发出，
    /// 所以要在服务端拒绝。没有 `Origin`（curl 等非浏览器客户端）放行。
    nonisolated static func isSameOrigin(origin: String?, host: String?) -> Bool {
        guard let origin = origin?.trimmingCharacters(in: .whitespaces), !origin.isEmpty else { return true }
        guard let host = host?.trimmingCharacters(in: .whitespaces).lowercased(), !host.isEmpty,
              let url = URL(string: origin), url.scheme?.lowercased() == "http",
              let originHost = url.host?.lowercased() else { return false }
        let originAuthority = url.port.map { "\(originHost):\($0)" } ?? originHost
        return originAuthority == host
    }

    private func allowsUpload(headers: Data) -> Bool {
        session.allowsUpload(authorizationHeader: extractHeader(from: headers, key: "Authorization"))
    }

    private func extractHeader(from data: Data, key: String) -> String? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        let lines = str.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix(key.lowercased() + ":") {
                return line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractBoundary(from contentType: String) -> String? {
        for part in contentType.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("boundary=") {
                return String(trimmed.dropFirst("boundary=".count))
            }
        }
        return nil
    }

    private func extractFilenameFromHeader(_ header: String) -> String? {
        let pattern = #"filename="?([^";\r\n]+)"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let range = Range(match.range(at: 1), in: header) else { return nil }
        return String(header[range])
    }
}

// MARK: - Streaming Upload Context

private final class StreamingUploadContext: @unchecked Sendable {
    let contentLength: Int
    let boundary: String
    let tempFileURL: URL
    let fileHandle: FileHandle
    var bytesReceived: Int = 0
    let startTime: Date = Date()

    init(contentLength: Int, boundary: String, tempFileURL: URL, fileHandle: FileHandle) {
        self.contentLength = contentLength
        self.boundary = boundary
        self.tempFileURL = tempFileURL
        self.fileHandle = fileHandle
    }
}

// MARK: - Data Extension

private extension Data {
    func components(separatedBy separator: Data) -> [Data] {
        var result: [Data] = []
        var start = startIndex
        while let range = self[start...].range(of: separator) {
            result.append(self[start..<range.lowerBound])
            start = range.upperBound
        }
        result.append(self[start...])
        return result
    }
}

// MARK: - Supporting Types

enum WiFiConnectionState: Equatable {
    case idle
    case connected(ip: String)
    case transferring(ip: String)
}

struct WiFiTransferProgress {
    let fileName: String
    let bytesReceived: Int64
    let totalBytes: Int64
    let speed: Double
}

enum WiFiSecurityAlert: Equatable {
    case unknownDeviceAttempt(ip: String)
    case bruteForceDetected(ip: String, attemptCount: Int)
    case newDeviceWhileTransferring(ip: String)
}

enum WiFiTransferHTML {
    private static let authSectionHTML = """
    <div id="authSection">
      <p style="font-size:14px;color:#374151">请输入访问密码：</p>
      <input type="password" id="pwdInput" placeholder="6位数字密码" maxlength="6">
      <button class="btn" onclick="doAuth()">验证密码</button>
    </div>
    <div id="uploadSection" class="hidden">
    """
    private static let noAuthSectionHTML = "<div id='uploadSection'>"

    static func page(address: String, passwordRequired: Bool) -> String {
        let authSection = passwordRequired ? authSectionHTML : noAuthSectionHTML
        if let url = Bundle.main.url(forResource: "wifi_transfer", withExtension: "html"),
           let template = try? String(contentsOf: url, encoding: .utf8) {
            return template.replacingOccurrences(of: "{{AUTH_SECTION}}", with: authSection)
        }
        return "<html><body><h1>WiFi Transfer</h1><p>Template not found</p></body></html>"
    }
}

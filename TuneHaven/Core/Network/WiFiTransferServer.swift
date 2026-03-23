import Darwin
import Foundation
import Network

@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var serverAddress: String?
    @Published private(set) var password: String?
    @Published private(set) var connectionState: WiFiConnectionState = .idle
    @Published private(set) var transferProgress: WiFiTransferProgress?
    @Published private(set) var securityAlert: WiFiSecurityAlert?
    private let log = AppLogger.shared

    var onFileReceived: ((String, URL) -> Void)?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var passwordEnabled = false
    private var failedAttempts = 0
    private var cooldownUntil: Date?
    private var port: UInt16 = 8080

    // MARK: - Lifecycle

    func start(passwordEnabled: Bool) throws {
        guard !isRunning else { return }
        log.info("WiFi 传输服务启动")
        self.passwordEnabled = passwordEnabled
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
    }

    func regeneratePassword() -> String {
        let pwd = generateRandomPassword()
        password = pwd
        return pwd
    }

    func setCustomPassword(_ pwd: String) throws {
        guard pwd.count >= 6, pwd.allSatisfy({ $0.isNumber }) else {
            throw AppError.wifiPasswordWrong
        }
        password = pwd
    }

    static func cleanupTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix("wifi_upload_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        guard case let .hostPort(host, _) = connection.endpoint else { return }
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
        failedAttempts = 0

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .failed = state { self?.connectionState = .idle }
                if case .cancelled = state { self?.connectionState = .idle }
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

                        if self.isUploadRequest(headers),
                           let ctx = self.beginStreamingUpload(headers: Data(headers), ip: ip) {
                            if !overflow.isEmpty {
                                ctx.fileHandle.write(Data(overflow))
                                ctx.bytesReceived = overflow.count
                                self.updateTransferProgress(ctx)
                            }
                            self.bodyReadLoop(context: ctx, connection: connection)
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
        if let cooldown = cooldownUntil, Date() < cooldown {
            sendJSON(connection: connection, status: 429, body: #"{"error":"请稍后再试"}"#)
            return
        }

        if let cooldown = cooldownUntil, Date() >= cooldown {
            failedAttempts = 0
            cooldownUntil = nil
        }

        guard let body = extractBody(from: data),
              let pwd = extractField(body, key: "password") else {
            sendJSON(connection: connection, status: 400, body: #"{"error":"缺少密码"}"#)
            return
        }

        if passwordEnabled && pwd != (password ?? "") {
            failedAttempts += 1
            if failedAttempts >= 5 {
                cooldownUntil = Date().addingTimeInterval(30)
                securityAlert = .bruteForceDetected(ip: ip, attemptCount: failedAttempts)
                sendJSON(connection: connection, status: 429, body: #"{"error":"密码错误次数过多，请等待30秒"}"#)
            } else {
                sendJSON(connection: connection, status: 401, body: #"{"error":"密码错误"}"#)
            }
            return
        }

        failedAttempts = 0
        sendJSON(connection: connection, status: 200, body: #"{"success":true}"#)
    }

    // MARK: - Upload (fallback for small in-memory requests)

    private func handleUpload(data: Data, connection: NWConnection) {
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

        for part in parts {
            guard let headerEnd = part.range(of: headerSeparator) else { continue }
            let headerData = part[part.startIndex..<headerEnd.lowerBound]
            let fileData = part[headerEnd.upperBound...]
            guard let headerStr = String(data: headerData, encoding: .utf8),
                  headerStr.contains("filename=") else { continue }

            let rawFilename = extractFilenameFromHeader(headerStr) ?? "uploaded_file"
            let filename = URL(fileURLWithPath: rawFilename).lastPathComponent
            let destURL = SandboxPathManager.wifiUploadURL.appendingPathComponent(filename)
            do {
                try fileData.write(to: destURL)
            } catch {
                AppLogger.shared.error(error, context: "WiFi上传文件写入失败: \(filename)")
                sendJSON(connection: connection, status: 500, body: #"{"error":"文件写入失败"}"#)
                return
            }

            connectionState = .idle
            sendJSON(connection: connection, status: 200, body: #"{"success":true}"#)
            onFileReceived?(filename, destURL)
            return
        }
        sendJSON(connection: connection, status: 400, body: #"{"error":"未找到文件"}"#)
    }

    // MARK: - HTTP Response

    private func sendHTML(connection: NWConnection) {
        let html = WiFiTransferHTML.page(address: serverAddress ?? "", passwordRequired: passwordEnabled)
        guard let bodyData = html.data(using: .utf8) else { return }
        let response = buildHTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: bodyData)
        connection.send(content: response, completion: .idempotent)
    }

    private func sendJSON(connection: NWConnection, status: Int, body: String) {
        guard let bodyData = body.data(using: .utf8) else { return }
        let response = buildHTTPResponse(status: status, contentType: "application/json", body: bodyData)
        connection.send(content: response, completion: .idempotent)
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
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        case 429: statusText = "Too Many Requests"
        case 500: statusText = "Internal Server Error"
        default: statusText = "OK"
        }
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
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
            if flags & (IFF_UP | IFF_RUNNING) != 0 && flags & IFF_LOOPBACK == 0 {
                let family = current.pointee.ifa_addr.pointee.sa_family
                if family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(current.pointee.ifa_addr, socklen_t(current.pointee.ifa_addr.pointee.sa_len),
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
        String((0..<6).map { _ in String(Int.random(in: 0...9)) }.joined())
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

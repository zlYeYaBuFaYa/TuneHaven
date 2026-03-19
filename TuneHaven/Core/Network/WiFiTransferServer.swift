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

    private func receiveHTTPRequest(connection: NWConnection, ip: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.handleHTTPData(data, connection: connection, ip: ip)
                }
                if isComplete { self.connectionState = .idle }
            }
        }
    }

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

    private func handleAuth(data: Data, connection: NWConnection, ip: String) {
        if let cooldown = cooldownUntil, Date() < cooldown {
            sendJSON(connection: connection, status: 429, body: #"{"error":"请稍后再试"}"#)
            return
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

    private func parseMultipart(bodyData: Data, boundary: String, connection: NWConnection) {
        let boundaryData = ("--" + boundary).data(using: .utf8)!
        let parts = bodyData.components(separatedBy: boundaryData)

        for part in parts {
            guard let headerEnd = part.range(of: "\r\n\r\n".data(using: .utf8)!) else { continue }
            let headerData = part[part.startIndex..<headerEnd.lowerBound]
            let fileData = part[headerEnd.upperBound...]
            guard let headerStr = String(data: headerData, encoding: .utf8),
                  headerStr.contains("filename=") else { continue }

            let filename = extractFilenameFromHeader(headerStr) ?? "uploaded_file"
            let destURL = SandboxPathManager.wifiUploadURL.appendingPathComponent(filename)
            try? Data(fileData).write(to: destURL)

            connectionState = .idle
            sendJSON(connection: connection, status: 200, body: #"{"success":true}"#)
            onFileReceived?(filename, destURL)
            return
        }
        sendJSON(connection: connection, status: 400, body: #"{"error":"未找到文件"}"#)
    }

    private func sendHTML(connection: NWConnection) {
        let html = WiFiTransferHTML.page(address: serverAddress ?? "", passwordRequired: passwordEnabled)
        let response = buildHTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: html.data(using: .utf8)!)
        connection.send(content: response, completion: .idempotent)
    }

    private func sendJSON(connection: NWConnection, status: Int, body: String) {
        let response = buildHTTPResponse(status: status, contentType: "application/json", body: body.data(using: .utf8)!)
        connection.send(content: response, completion: .idempotent)
    }

    private func sendStatus(connection: NWConnection) {
        let json = #"{"isRunning":true}"#
        sendJSON(connection: connection, status: 200, body: json)
    }

    private func send404(connection: NWConnection) {
        sendJSON(connection: connection, status: 404, body: #"{"error":"not found"}"#)
    }

    private func buildHTTPResponse(status: Int, contentType: String, body: Data) -> Data {
        let header = "HTTP/1.1 \(status) OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        var response = header.data(using: .utf8)!
        response.append(body)
        return response
    }

    private func resolveLocalIP() -> String? {
        var address: String?
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
                        address = String(cString: hostname)
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return address.map { "http://\($0):\(port)" }
    }

    private func generateRandomPassword() -> String {
        String((0..<6).map { _ in String(Int.random(in: 0...9)) }.joined())
    }

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

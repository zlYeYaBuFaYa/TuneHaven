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

    var onFileReceived: ((String, URL) -> Void)?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var passwordEnabled = false
    private var failedAttempts = 0
    private var cooldownUntil: Date?
    private var port: UInt16 = 8080

    func start(passwordEnabled: Bool) throws {
        guard !isRunning else { return }
        self.passwordEnabled = passwordEnabled
        if passwordEnabled && password == nil { password = generateRandomPassword() }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
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
    static func page(address: String, passwordRequired: Bool) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>音乐传输</title>
        <style>body{font-family:system-ui;max-width:500px;margin:40px auto;padding:20px;background:#f5f5f5}
        .card{background:#fff;border-radius:12px;padding:24px;box-shadow:0 2px 12px rgba(0,0,0,.1)}
        h1{color:#10B981;margin-bottom:8px}
        .warn{background:#FFF7ED;border:1px solid #FED7AA;border-radius:8px;padding:12px;margin-bottom:16px;color:#9A3412}
        input[type=text],input[type=password]{width:100%;padding:10px;border:1px solid #ddd;border-radius:8px;box-sizing:border-box;margin:8px 0}
        button{background:#10B981;color:#fff;border:none;padding:12px 24px;border-radius:8px;cursor:pointer;width:100%;font-size:16px}
        button:hover{background:#059669}
        #drop{border:2px dashed #10B981;border-radius:12px;padding:40px;text-align:center;color:#6b7280;margin-top:16px}
        #drop.drag{background:#F0FDF4;border-color:#059669}
        #progress{margin-top:12px;display:none}
        progress{width:100%;height:8px}</style></head>
        <body>
        <div class="card">
          <h1>🎵 音乐传输</h1>
          <div class="warn">⚠️ 仅在可信WiFi网络中使用，HTTP传输可能被网络监听</div>
          \(passwordRequired ? """
          <div id="authSection">
            <p>请输入访问密码：</p>
            <input type="password" id="pwdInput" placeholder="6位数字密码" maxlength="6">
            <button onclick="doAuth()">验证</button>
          </div>
          <div id="uploadSection" style="display:none">
          """ : "<div id='uploadSection'>")
          <div id="drop">拖拽文件到此处，或点击选择文件<br>
            <input type="file" id="fileInput" multiple accept=".mp3,.m4a,.aac,.wav,.alac" style="margin-top:12px">
          </div>
          <div id="progress"><progress id="bar" value="0" max="100"></progress><p id="status"></p></div>
          </div>
        </div>
        <script>
        function doAuth(){
          const pwd=document.getElementById('pwdInput').value;
          fetch('/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:pwd})})
            .then(r=>r.json()).then(d=>{
              if(d.success){document.getElementById('authSection').style.display='none';document.getElementById('uploadSection').style.display='block';}
              else alert('密码错误，请重试');
            }).catch(()=>alert('连接失败'));
        }
        const drop=document.getElementById('drop');
        const fileInput=document.getElementById('fileInput');
        drop.addEventListener('dragover',e=>{e.preventDefault();drop.classList.add('drag');});
        drop.addEventListener('dragleave',()=>drop.classList.remove('drag'));
        drop.addEventListener('drop',e=>{e.preventDefault();drop.classList.remove('drag');uploadFiles(e.dataTransfer.files);});
        fileInput.addEventListener('change',()=>uploadFiles(fileInput.files));
        function uploadFiles(files){
          if(!files.length)return;
          Array.from(files).forEach(file=>{
            const fd=new FormData();fd.append('file',file);
            const xhr=new XMLHttpRequest();
            xhr.upload.onprogress=e=>{
              if(e.lengthComputable){
                document.getElementById('progress').style.display='block';
                document.getElementById('bar').value=e.loaded/e.total*100;
                document.getElementById('status').textContent=file.name+' '+Math.round(e.loaded/e.total*100)+'%';
              }
            };
            xhr.onload=()=>{document.getElementById('status').textContent=file.name+' 上传完成✓';};
            xhr.onerror=()=>{document.getElementById('status').textContent=file.name+' 上传失败';};
            xhr.open('POST','/upload');xhr.send(fd);
          });
        }
        </script></body></html>
        """
    }
}

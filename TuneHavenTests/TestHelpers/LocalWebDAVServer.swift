import Foundation
import Network

/// 测试用的最小 WebDAV 服务器：本机回环、随机端口，支持 Basic 认证与
/// OPTIONS / PROPFIND（Depth 0、1）/ GET / HEAD。每个响应后关闭连接。
/// 文件按路径登记，目录由路径自动推出；`slowPaths` 里的文件按小块慢速发送，用来测试中途取消。
final class LocalWebDAVServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let authorization: String?
        let depth: String?
    }

    let username: String
    let password: String
    private let queue = DispatchQueue(label: "LocalWebDAVServer")
    private let listener: NWListener
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var slowPaths: Set<String> = []
    private var _requests: [Request] = []
    private var connections: [NWConnection] = []

    var requests: [Request] { lock.withLock { _requests } }
    private(set) var port: UInt16 = 0

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/dav/")! }

    init(username: String = "user", password: String = "secret") throws {
        self.username = username
        self.password = password
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    self?.port = self?.listener.port?.rawValue ?? 0
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.withLock { connections.forEach { $0.cancel() } }
    }

    /// `path` 为服务器上的绝对路径，如 `/dav/Music/a.mp3`。
    func addFile(_ path: String, data: Data, slow: Bool = false) {
        lock.withLock {
            files[path] = data
            if slow { slowPaths.insert(path) }
        }
    }

    // MARK: - Connection

    private func accept(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                let length = Int(Self.header("Content-Length", in: head) ?? "") ?? 0
                if buffer.count - headerEnd.upperBound >= length {
                    self.respond(to: head, on: connection)
                    return
                }
            }
            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return send(status: 400, on: connection) }
        let method = String(parts[0])
        let rawPath = String(parts[1]).components(separatedBy: "?")[0]
        let path = rawPath.removingPercentEncoding ?? rawPath
        let authorization = Self.header("Authorization", in: head)
        lock.withLock {
            _requests.append(Request(method: method, path: path, authorization: authorization,
                                     depth: Self.header("Depth", in: head)))
        }

        let expected = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
        guard authorization == expected else {
            return send(status: 401, headers: ["WWW-Authenticate": #"Basic realm="test""#], on: connection)
        }

        switch method {
        case "OPTIONS":
            send(status: 200, headers: ["DAV": "1, 2", "Allow": "OPTIONS, GET, HEAD, PROPFIND"], on: connection)
        case "PROPFIND":
            guard let body = multistatus(for: path, depth: Self.header("Depth", in: head) ?? "1") else {
                return send(status: 404, on: connection)
            }
            send(status: 207, headers: ["Content-Type": "application/xml; charset=utf-8"], body: body, on: connection)
        case "GET", "HEAD":
            let (data, slow) = lock.withLock { (files[path], slowPaths.contains(path)) }
            guard let data else { return send(status: 404, on: connection) }
            if method == "HEAD" {
                return send(status: 200, headers: ["ETag": "\"\(data.count)\""], declaredLength: data.count, on: connection)
            }
            if slow {
                sendSlowly(data, on: connection)
            } else {
                send(status: 200, headers: ["Content-Type": "application/octet-stream"], body: data, on: connection)
            }
        default:
            send(status: 405, on: connection)
        }
    }

    // MARK: - PROPFIND

    private func multistatus(for path: String, depth: String) -> Data? {
        let directory = path.hasSuffix("/") ? path : path + "/"
        let snapshot = lock.withLock { files }
        let isDirectory = snapshot.keys.contains { $0.hasPrefix(directory) }
        guard isDirectory || snapshot[path] != nil else { return nil }

        var entries: [(href: String, size: Int?)] = [(isDirectory ? directory : path, isDirectory ? nil : snapshot[path]?.count)]
        if isDirectory && depth != "0" {
            var children: [String: Int?] = [:]
            for (filePath, data) in snapshot where filePath.hasPrefix(directory) {
                let rest = filePath.dropFirst(directory.count)
                if let slash = rest.firstIndex(of: "/") {
                    children[directory + rest[..<slash] + "/"] = .some(nil)
                } else {
                    children[filePath] = data.count
                }
            }
            entries += children.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }

        var xml = #"<?xml version="1.0" encoding="UTF-8"?><d:multistatus xmlns:d="DAV:">"#
        for entry in entries {
            let encoded = entry.href.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.href
            let name = (entry.href as NSString).lastPathComponent
            xml += "<d:response><d:href>\(encoded)</d:href><d:propstat><d:prop>"
            xml += "<d:displayname>\(name)</d:displayname>"
            if let size = entry.size {
                xml += "<d:getcontentlength>\(size)</d:getcontentlength><d:resourcetype/>"
            } else {
                xml += "<d:resourcetype><d:collection/></d:resourcetype>"
            }
            xml += "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
        }
        xml += "</d:multistatus>"
        return Data(xml.utf8)
    }

    // MARK: - Responses

    private func send(status: Int, headers: [String: String] = [:], body: Data = Data(),
                      declaredLength: Int? = nil, on connection: NWConnection) {
        var data = Self.head(status: status, headers: headers, length: declaredLength ?? body.count)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// 每 20ms 发 16KB，客户端有足够时间在中途取消。
    private func sendSlowly(_ body: Data, on connection: NWConnection) {
        let head = Self.head(status: 200, headers: ["Content-Type": "application/octet-stream"], length: body.count)
        connection.send(content: head, completion: .contentProcessed { _ in })
        func next(_ offset: Int) {
            guard offset < body.count else {
                connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let end = min(offset + 16_384, body.count)
            connection.send(content: body[offset..<end], completion: .contentProcessed { [queue] error in
                guard error == nil else { return }
                queue.asyncAfter(deadline: .now() + 0.02) { next(end) }
            })
        }
        next(0)
    }

    private static func head(status: Int, headers: [String: String], length: Int) -> Data {
        let reason = [200: "OK", 207: "Multi-Status", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "Error"
        var text = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(length)\r\nConnection: close\r\n"
        for (key, value) in headers { text += "\(key): \(value)\r\n" }
        return Data((text + "\r\n").utf8)
    }

    private static func header(_ name: String, in head: String) -> String? {
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].caseInsensitiveCompare(name) == .orderedSame {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

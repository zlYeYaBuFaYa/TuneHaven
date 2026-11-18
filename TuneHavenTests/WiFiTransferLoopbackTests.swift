import Foundation
import Testing
@testable import TuneHaven

@Suite("WiFi 上传：同源判断")
struct WiFiSameOriginTests {
    @Test("无 Origin（非浏览器）放行，同源放行")
    func allowsMissingOrSameOrigin() {
        #expect(WiFiTransferServer.isSameOrigin(origin: nil, host: "192.168.1.5:8080"))
        #expect(WiFiTransferServer.isSameOrigin(origin: "http://192.168.1.5:8080", host: "192.168.1.5:8080"))
        #expect(WiFiTransferServer.isSameOrigin(origin: "HTTP://Device.local:8080", host: "device.local:8080"))
    }

    @Test("其他站点、端口不同、null 与 https 都拒绝")
    func rejectsCrossOrigin() {
        #expect(WiFiTransferServer.isSameOrigin(origin: "http://evil.example", host: "192.168.1.5:8080") == false)
        #expect(WiFiTransferServer.isSameOrigin(origin: "http://192.168.1.5:9000", host: "192.168.1.5:8080") == false)
        #expect(WiFiTransferServer.isSameOrigin(origin: "null", host: "192.168.1.5:8080") == false)
        #expect(WiFiTransferServer.isSameOrigin(origin: "https://192.168.1.5:8080", host: "192.168.1.5:8080") == false)
        #expect(WiFiTransferServer.isSameOrigin(origin: "http://192.168.1.5:8080", host: nil) == false)
    }
}

/// 在本机回环地址上跑真实的 WiFiTransferServer。每个用例用不同端口，上一个监听关闭是异步的。
@MainActor
@Suite("WiFi 传输服务器：回环连接", .serialized)
struct WiFiTransferLoopbackTests {

    private func startServer(port: UInt16) async throws -> WiFiTransferServer {
        let server = WiFiTransferServer(port: port)
        try server.start(passwordEnabled: false)
        let deadline = ContinuousClock.now + .seconds(2)
        while !server.isRunning && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(server.isRunning)
        return server
    }

    private func request(_ raw: String, port: UInt16) async throws -> String? {
        let client = LoopbackClient(port: port)
        try await client.connect()
        await client.send(raw)
        return await client.receiveUntilClosed().map { String(decoding: $0, as: UTF8.self) }
    }

    @Test("JSON 响应后关闭连接，且不带 CORS 放行头")
    func jsonResponseClosesWithoutCORS() async throws {
        let server = try await startServer(port: 18081)
        defer { server.stop() }

        let response = try #require(await request("GET /heartbeat HTTP/1.1\r\nHost: 127.0.0.1:18081\r\n\r\n", port: 18081))

        #expect(response.hasPrefix("HTTP/1.1 200"))
        #expect(!response.localizedCaseInsensitiveContains("Access-Control-Allow-Origin"))
    }

    @Test("请求头超过 16KB：回 400 并关闭连接")
    func oversizedHeaderClosesConnection() async throws {
        let server = try await startServer(port: 18082)
        defer { server.stop() }

        let padding = String(repeating: "a", count: 20_000)
        let response = try #require(await request("GET /heartbeat HTTP/1.1\r\nX-Pad: \(padding)", port: 18082))

        #expect(response.hasPrefix("HTTP/1.1 400"))
    }

    @Test("跨站页面的上传请求回 403，不接收文件")
    func crossOriginUploadRejected() async throws {
        let server = try await startServer(port: 18083)
        defer { server.stop() }
        var received: [String] = []
        server.onFileReceived = { name, _ in received.append(name) }

        let body = "--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.mp3\"\r\n\r\nabc\r\n--b--\r\n"
        let raw = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1:18083\r\nOrigin: http://evil.example\r\n"
            + "Content-Type: multipart/form-data; boundary=b\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let response = try #require(await request(raw, port: 18083))

        #expect(response.hasPrefix("HTTP/1.1 403"))
        #expect(received.isEmpty)
    }

    @Test("同源上传照常接收")
    func sameOriginUploadAccepted() async throws {
        let server = try await startServer(port: 18084)
        defer { server.stop() }
        var received: [(String, URL)] = []
        server.onFileReceived = { name, url in received.append((name, url)) }
        defer { received.forEach { try? FileManager.default.removeItem(at: $0.1) } }

        let body = "--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.mp3\"\r\n\r\nabc\r\n--b--\r\n"
        let raw = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1:18084\r\nOrigin: http://127.0.0.1:18084\r\n"
            + "Content-Type: multipart/form-data; boundary=b\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let response = try #require(await request(raw, port: 18084))

        #expect(response.hasPrefix("HTTP/1.1 200"))
        #expect(received.map(\.0) == ["a.mp3"])
    }
}

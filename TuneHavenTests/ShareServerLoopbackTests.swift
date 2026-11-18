import Foundation
import Network
import Testing
@testable import TuneHaven

/// 在本机回环地址上跑真实的 ShareServer，验证连接层行为。
@MainActor
@Suite("分享服务器：回环连接", .serialized)
struct ShareServerLoopbackTests {

    @Test("未授权的新连接不会打断正在下载的已授权连接")
    func unauthorizedConnectionDoesNotInterruptTransfer() async throws {
        let fileSize = 32 * 1024 * 1024
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-loopback-\(UUID().uuidString).mp3")
        try Data(count: fileSize).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let server = ShareServer()
        let dataSource = SingleFileDataSource(audioURL: fileURL)
        server.dataSource = dataSource
        try await server.start()
        defer { server.stop() }
        let token = try #require(server.qrCodeContent?.components(separatedBy: "token=").last)

        // 已授权连接开始下载，只读一点就停，让服务端因背压停在传输中途
        let downloader = LoopbackClient()
        try await downloader.connect()
        await downloader.send("GET /api/share/song/0/audio HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer \(token)\r\n\r\n")
        var received = try #require(await downloader.receive())

        // 局域网里另一台设备拿错误 token 连进来
        let intruder = LoopbackClient()
        try await intruder.connect()
        await intruder.send("GET /api/share/info HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer wrong\r\n\r\n")
        let rejection = String(decoding: await intruder.receiveAll(), as: UTF8.self)
        #expect(rejection.hasPrefix("HTTP/1.1 401"))

        while let chunk = await downloader.receive() {
            received.append(chunk)
        }
        let headerEnd = try #require(received.range(of: Data("\r\n\r\n".utf8)))
        #expect(received.count - headerEnd.upperBound == fileSize)
    }
}

@MainActor
private final class SingleFileDataSource: ShareDataSource {
    let audioURL: URL
    init(audioURL: URL) { self.audioURL = audioURL }

    func sessionInfo() -> ShareSessionInfo {
        ShareSessionInfo(deviceName: "Test", sessionToken: "", songCount: 1, playlistCount: 0, totalSize: 0)
    }
    func songSummaries() -> [ShareSongSummary] { [] }
    func playlistSummaries() -> [SharePlaylistSummary] { [] }
    func audioFileURL(at index: Int) -> URL? { index == 0 ? audioURL : nil }
    func coverFileURL(at index: Int) -> URL? { nil }
    func lyricsFileURL(at index: Int) -> URL? { nil }
    func playlistSongs(at index: Int) -> [ShareSongSummary] { [] }
    func songExportData(at index: Int) -> SongExportData? { nil }
}

/// 最小 TCP 客户端：手动控制读取节奏，用来制造传输中途的状态。
private final class LoopbackClient: @unchecked Sendable {
    private let connection = NWConnection(host: "127.0.0.1", port: 8090, using: .tcp)
    private let queue = DispatchQueue(label: "LoopbackClient")

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error), .waiting(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func send(_ text: String) async {
        await withCheckedContinuation { continuation in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    /// 返回 nil 表示服务端已关闭连接。
    func receive() async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete || error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func receiveAll() async -> Data {
        var all = Data()
        while let chunk = await receive() { all.append(chunk) }
        return all
    }

    deinit { connection.cancel() }
}

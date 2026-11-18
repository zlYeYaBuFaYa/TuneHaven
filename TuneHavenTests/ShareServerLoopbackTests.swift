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
        let downloader = LoopbackClient(port: 8090)
        try await downloader.connect()
        await downloader.send("GET /api/share/song/0/audio HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer \(token)\r\n\r\n")
        var received = try #require(await downloader.receive())

        // 局域网里另一台设备拿错误 token 连进来
        let intruder = LoopbackClient(port: 8090)
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

import Testing
import Foundation
@testable import TuneHaven

// MARK: - ShareClient 本地文件命名（URLProtocol 桩）

@Suite("ShareClient 不信任发送端文件名")
struct ShareClientTests {

    private static let qr = "http://share.test:8090?token=t0ken"

    private static func stubSessionInfo() throws {
        let info = ShareSessionInfo(deviceName: "Sender", sessionToken: "", songCount: 1, playlistCount: 0, totalSize: 1)
        StubURLProtocol.set(.init(body: try JSONEncoder().encode(info)), for: "/api/share/info")
    }

    private static func stubFile(_ path: String, disposition: String?, body: String = "data", status: Int = 200) {
        var headers: [String: String] = [:]
        if let disposition { headers["Content-Disposition"] = disposition }
        StubURLProtocol.set(.init(status: status, body: Data(body.utf8), headers: headers), for: path)
    }

    /// 返回 (receive 目录, 其上级目录)。上级目录里放一个哨兵文件，验证没有被删除。
    private func makeDirs() throws -> (dir: URL, parent: URL, sentinel: URL) {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareClientTests-\(UUID().uuidString)", isDirectory: true)
        let dir = parent.appendingPathComponent("receive", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sentinel = parent.appendingPathComponent("sentinel.txt")
        try Data("keep".utf8).write(to: sentinel)
        return (dir, parent, sentinel)
    }

    private func connectedClient() async throws -> ShareClient {
        try Self.stubSessionInfo()
        let client = ShareClient(sessionConfiguration: StubURLProtocol.sessionConfiguration())
        _ = try await client.connect(to: Self.qr)
        return client
    }

    private func contents(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    @Test("发送端文件名为 .. 时保存在目标目录内，上级目录不受影响")
    func testDotDotFilename() async throws {
        let (dir, parent, sentinel) = try makeDirs()
        defer { try? FileManager.default.removeItem(at: parent) }
        Self.stubFile("/api/share/song/0/audio", disposition: #"attachment; filename="..""#)
        let client = try await connectedClient()

        let url = try await client.downloadAudio(at: 0, to: dir) { _ in }

        #expect(url.lastPathComponent == "audio_0.dat")
        #expect(url.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("带路径的文件名只取扩展名，保存在目标目录内")
    func testPathTraversalFilename() async throws {
        let (dir, parent, sentinel) = try makeDirs()
        defer { try? FileManager.default.removeItem(at: parent) }
        Self.stubFile("/api/share/song/1/audio", disposition: #"attachment; filename="../../evil.mp3""#)
        let client = try await connectedClient()

        let url = try await client.downloadAudio(at: 1, to: dir) { _ in }

        #expect(url.lastPathComponent == "audio_1.mp3")
        #expect(contents(dir) == ["audio_1.mp3"])
        #expect(contents(parent) == ["receive", "sentinel.txt"])
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test("音频扩展名不在白名单时用 dat")
    func testDisallowedAudioExtension() async throws {
        let (dir, parent, _) = try makeDirs()
        defer { try? FileManager.default.removeItem(at: parent) }
        Self.stubFile("/api/share/song/2/audio", disposition: #"attachment; filename="x.exe""#)
        let client = try await connectedClient()

        let url = try await client.downloadAudio(at: 2, to: dir) { _ in }

        #expect(url.lastPathComponent == "audio_2.dat")
    }

    @Test("封面与歌词按类型命名，扩展名转小写，支持 filename* 编码")
    func testCoverAndLyricsNames() async throws {
        let (dir, parent, _) = try makeDirs()
        defer { try? FileManager.default.removeItem(at: parent) }
        Self.stubFile("/api/share/song/5/cover", disposition: #"attachment; filename="A.PNG""#)
        Self.stubFile("/api/share/song/5/lyrics", disposition: "attachment; filename*=utf-8''%E6%AD%8C.lrc")
        let client = try await connectedClient()

        let cover = try await client.downloadCover(at: 5, to: dir)
        let lyrics = try await client.downloadLyrics(at: 5, to: dir)

        #expect(cover?.lastPathComponent == "cover_5.png")
        #expect(lyrics?.lastPathComponent == "lyrics_5.lrc")
        #expect(contents(dir) == ["cover_5.png", "lyrics_5.lrc"])
    }

    @Test("可选下载 404 时返回 nil，不留文件")
    func testOptionalNotFound() async throws {
        let (dir, parent, _) = try makeDirs()
        defer { try? FileManager.default.removeItem(at: parent) }
        Self.stubFile("/api/share/song/6/cover", disposition: nil, status: 404)
        let client = try await connectedClient()

        let cover = try await client.downloadCover(at: 6, to: dir)

        #expect(cover == nil)
        #expect(contents(dir).isEmpty)
    }

    @Test("没有 Content-Disposition 时用默认扩展名")
    func testLocalFilenameDefaults() throws {
        let url = try #require(URL(string: "http://share.test/x"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:]))

        #expect(ShareClient.localFilename(for: response, kind: .audio, index: 7) == "audio_7.dat")
        #expect(ShareClient.localFilename(for: response, kind: .cover, index: 7) == "cover_7.jpg")
        #expect(ShareClient.localFilename(for: response, kind: .lyrics, index: 7) == "lyrics_7.lrc")
    }
}

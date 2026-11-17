import Testing
import Foundation
@testable import TuneHaven

@Suite("WiFi 上传令牌")
struct WiFiTransferSessionTests {

    @Test("密码关闭时，没有请求头也允许上传")
    func testPasswordOffAllowsUpload() {
        var session = WiFiTransferSession()
        session.passwordEnabled = false
        #expect(session.allowsUpload(authorizationHeader: nil))
    }

    @Test("密码开启但尚未签发 token 时拒绝上传")
    func testPasswordOnWithoutTokenDenies() {
        var session = WiFiTransferSession()
        session.passwordEnabled = true
        #expect(session.allowsUpload(authorizationHeader: "Bearer anything") == false)
    }

    @Test("正确的 Bearer token 允许上传，错误前缀或错误 token 拒绝")
    func testBearerToken() {
        var session = WiFiTransferSession()
        session.passwordEnabled = true
        let token = session.issueUploadToken()

        #expect(session.allowsUpload(authorizationHeader: "Bearer \(token)"))
        #expect(session.allowsUpload(authorizationHeader: token) == false)
        #expect(session.allowsUpload(authorizationHeader: "Bearer other") == false)
        #expect(session.allowsUpload(authorizationHeader: nil) == false)
    }

    @Test("作废后原来的 token 不能再上传")
    func testInvalidateToken() {
        var session = WiFiTransferSession()
        session.passwordEnabled = true
        let token = session.issueUploadToken()
        session.invalidateUploadToken()
        #expect(session.allowsUpload(authorizationHeader: "Bearer \(token)") == false)
    }
}

@Suite("WiFi 上传落盘")
struct WiFiUploadFileTests {

    @Test("同名文件两次落盘得到不同路径，都在目标目录内并保留原文件名")
    func testUploadDestinationIsUnique() {
        let dir = URL(fileURLWithPath: "/tmp/wifi_upload", isDirectory: true)

        let first = WiFiTransferServer.uploadDestination(for: "01.mp3", in: dir)
        let second = WiFiTransferServer.uploadDestination(for: "01.mp3", in: dir)

        #expect(first != second)
        #expect(first.deletingLastPathComponent().path == dir.path)
        #expect(second.deletingLastPathComponent().path == dir.path)
        #expect(first.lastPathComponent.hasSuffix("-01.mp3"))
    }

    @Test("文件名只取最后一段，非法名退回 uploaded_file")
    func testSafeFilename() {
        #expect(WiFiTransferServer.safeFilename("../x.mp3") == "x.mp3")
        #expect(WiFiTransferServer.safeFilename("a/b/c.flac") == "c.flac")
        #expect(WiFiTransferServer.safeFilename("..") == "uploaded_file")
        #expect(WiFiTransferServer.safeFilename(".") == "uploaded_file")
        #expect(WiFiTransferServer.safeFilename("") == "uploaded_file")
    }

    @Test("启动清理清空 wifi_upload 目录")
    func testCleanupRemovesUploads() throws {
        let dir = SandboxPathManager.wifiUploadURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(UUID().uuidString)-a.mp3")
        try Data("x".utf8).write(to: file)

        WiFiTransferServer.cleanupTempFiles()

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

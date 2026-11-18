import Foundation
import Testing
@testable import TuneHaven

/// 在本机回环地址上跑真实 HTTP 往返，验证 WebDAVClient 的协议行为（认证、PROPFIND、下载、取消）。
@Suite("WebDAV：本机服务器集成", .serialized)
struct WebDAVLoopbackTests {

    private func makeServer() async throws -> LocalWebDAVServer {
        let server = try LocalWebDAVServer()
        server.addFile("/dav/Music/周杰伦/晴天.mp3", data: Data(repeating: 1, count: 2048))
        server.addFile("/dav/Music/a song.flac", data: Data(repeating: 2, count: 4096))
        server.addFile("/dav/readme.txt", data: Data("hi".utf8))
        try await server.start()
        return server
    }

    private func makeClient(_ server: LocalWebDAVServer, password: String? = nil) -> WebDAVClient {
        WebDAVClient(configuration: .init(baseURL: server.baseURL, username: server.username,
                                          password: password ?? server.password))
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("webdav-loop-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("测试连接：OPTIONS + PROPFIND Depth 0，带 Basic 认证")
    func testConnectionSucceeds() async throws {
        let server = try await makeServer()
        defer { server.stop() }

        #expect(try await makeClient(server).testConnection())

        let methods = server.requests.map(\.method)
        #expect(methods == ["OPTIONS", "PROPFIND"])
        #expect(server.requests.last?.depth == "0")
        #expect(server.requests.last?.path == "/dav/")
        #expect(server.requests.allSatisfy { $0.authorization?.hasPrefix("Basic ") == true })
    }

    @Test("密码错误：报认证失败")
    func wrongPasswordFailsAuth() async throws {
        let server = try await makeServer()
        defer { server.stop() }

        await #expect(throws: AppError.webdavAuthFailed) {
            _ = try await makeClient(server, password: "wrong").testConnection()
        }
    }

    @Test("列目录：返回子目录与文件，过滤自身，中文与空格路径可再次进入")
    func listDirectoryRoundTrip() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let client = makeClient(server)

        let music = try await client.listDirectory(path: "/dav/Music/")
        #expect(Set(music.map(\.fileName)) == ["周杰伦", "a song.flac"])
        let folder = try #require(music.first { $0.isDirectory })
        #expect(music.first { !$0.isDirectory }?.contentLength == 4096)

        let inner = try await client.listDirectory(path: folder.href)
        #expect(inner.map(\.fileName) == ["晴天.mp3"])
        #expect(server.requests.last?.path == "/dav/Music/周杰伦/")
    }

    @Test("下载：中文路径内容完整，进度到达总字节数；不存在的文件报错且不留文件")
    func downloadRoundTrip() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let client = makeClient(server)
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try await client.listDirectory(path: "/dav/Music/周杰伦/")
        let song = try #require(files.first)
        let last = LockedValue<(Int64, Int64)?>(nil)

        let url = try await client.downloadFile(remotePath: song.href, to: dir.appendingPathComponent("晴天.mp3")) { received, total in
            last.set((received, total))
        }

        #expect(try Data(contentsOf: url) == Data(repeating: 1, count: 2048))
        #expect(last.get()?.0 == 2048)

        let missing = dir.appendingPathComponent("missing.mp3")
        await #expect(throws: (any Error).self) {
            _ = try await client.downloadFile(remotePath: "/dav/none.mp3", to: missing) { _, _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("慢速下载中途取消：很快结束且不留下目标文件")
    func cancelSlowDownload() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        server.addFile("/dav/big.flac", data: Data(repeating: 3, count: 4 * 1024 * 1024), slow: true)
        let client = makeClient(server)
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dest = dir.appendingPathComponent("big.flac")
        let started = LockedValue(false)

        let download = Task {
            try await client.downloadFile(remotePath: "/dav/big.flac", to: dest) { received, _ in
                if received > 0 { started.set(true) }
            }
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while !started.get() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(started.get())

        let cancelledAt = ContinuousClock.now
        await client.cancelDownload()
        await #expect(throws: (any Error).self) { _ = try await download.value }
        #expect(ContinuousClock.now - cancelledAt < .seconds(2))
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }
}

/// 账户地址带路径时，连接后列出的是该路径而不是服务器根目录。
@MainActor
@Suite("WebDAV：服务层连接本机服务器", .serialized)
struct WebDAVServiceLoopbackTests {
    @Test("连接后列出账户路径下的目录，不是服务器根")
    func connectListsAccountRoot() async throws {
        let server = try LocalWebDAVServer()
        server.addFile("/dav/Music/a.mp3", data: Data([1]))
        server.addFile("/other/b.mp3", data: Data([2]))
        try await server.start()
        defer { server.stop() }

        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        let subscription = SubscriptionService(provider: provider)
        await subscription.refreshStatus()
        let store = SingleAccountStore(password: server.password)
        let account = WebDAVAccount(serverURL: server.baseURL.absoluteString, username: server.username)
        try store.saveAccount(account, password: server.password)
        let service = WebDAVService(accountStore: store, clientFactory: DefaultWebDAVClientFactory(),
                                    importService: NoopFileImporter(), fileStorage: MockFileStorageProviding(),
                                    subscriptionService: subscription)

        try await service.connect(to: account)

        #expect(service.rootPath == "/dav/")
        #expect(service.currentFiles.map(\.fileName) == ["Music"])
        #expect(server.requests.last { $0.method == "PROPFIND" }?.path == "/dav/")
    }
}

final class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
}

private final class SingleAccountStore: WebDAVAccountStoring {
    private var accounts: [WebDAVAccount] = []
    private let storedPassword: String
    init(password: String) { storedPassword = password }
    func loadAccounts() -> [WebDAVAccount] { accounts }
    func saveAccount(_ account: WebDAVAccount, password: String?) throws {
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
    }
    func deleteAccount(id: UUID) throws {}
    func password(for accountId: UUID) -> String? { storedPassword }
    func updateLastConnected(accountId: UUID) throws {}
}

@MainActor
private final class NoopFileImporter: FileImporting {
    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
        ImportResult(successCount: 0, skippedDuplicateCount: 0, skippedFormatCount: 0,
                     failedCount: 0, incompleteMetadataCount: 0, skippedOversizeCount: 0, details: [])
    }
}

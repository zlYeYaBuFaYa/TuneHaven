import Testing
import Foundation
@testable import TuneHaven

// MARK: - URLProtocol 桩：按路径返回固定响应，可设延迟

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status: Int = 200
        var body = Data()
        var delay: TimeInterval = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]

    static func set(_ response: Response, for path: String) {
        lock.lock(); defer { lock.unlock() }
        responses[path] = response
    }

    private static func response(for path: String) -> Response? {
        lock.lock(); defer { lock.unlock() }
        return responses[path]
    }

    private var workItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let stub = Self.response(for: path) ?? Response(status: 404)
        let item = DispatchWorkItem { [weak self] in
            guard let self, let url = self.request.url,
                  let http = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Length": "\(stub.body.count)"]) else { return }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: stub.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        workItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: item)
    }

    override func stopLoading() {
        workItem?.cancel()
    }
}

private func makeClient() -> WebDAVClient {
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [StubURLProtocol.self]
    return WebDAVClient(
        configuration: .init(
            baseURL: URL(string: "https://dav.test")!,
            username: "u",
            password: "p"
        ),
        sessionConfiguration: sessionConfig
    )
}

private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("WebDAVDownloadTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// MARK: - WebDAVClient

@Suite("WebDAVClient 下载")
struct WebDAVClientDownloadTests {

    @Test("同一 client 并发 3 个下载互不取消，全部成功")
    func testConcurrentDownloadsSucceed() async throws {
        let client = makeClient()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = ["c1.mp3", "c2.mp3", "c3.mp3"]
        for name in names {
            StubURLProtocol.set(.init(body: Data(name.utf8), delay: 0.2), for: "/concurrent/\(name)")
        }

        let results = try await withThrowingTaskGroup(of: (String, URL).self) { group in
            for name in names {
                group.addTask {
                    let url = try await client.downloadFile(
                        remotePath: "/concurrent/\(name)",
                        to: dir.appendingPathComponent(name)
                    ) { _, _ in }
                    return (name, url)
                }
            }
            var collected: [(String, URL)] = []
            for try await item in group { collected.append(item) }
            return collected
        }

        #expect(results.count == 3)
        for (name, url) in results {
            #expect((try? String(contentsOf: url, encoding: .utf8)) == name)
        }
    }

    @Test("下载中取消：抛错且不留下目标文件；之后仍可再次下载")
    func testCancelThenDownloadAgain() async throws {
        let client = makeClient()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        StubURLProtocol.set(.init(body: Data("slow".utf8), delay: 5), for: "/cancel/slow.mp3")
        StubURLProtocol.set(.init(body: Data("fast".utf8)), for: "/cancel/fast.mp3")
        let slowDest = dir.appendingPathComponent("slow.mp3")

        let download = Task {
            try await client.downloadFile(remotePath: "/cancel/slow.mp3", to: slowDest) { _, _ in }
        }
        try await Task.sleep(for: .milliseconds(200))
        await client.cancelDownload()

        await #expect(throws: (any Error).self) { try await download.value }
        #expect(!FileManager.default.fileExists(atPath: slowDest.path))

        let again = try await client.downloadFile(
            remotePath: "/cancel/fast.mp3",
            to: dir.appendingPathComponent("fast.mp3")
        ) { _, _ in }
        #expect((try? String(contentsOf: again, encoding: .utf8)) == "fast")
    }

    @Test("取消调用方任务时，取消传递到该下载，不留下目标文件")
    func testCallerCancellationPropagates() async throws {
        let client = makeClient()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        StubURLProtocol.set(.init(body: Data("slow".utf8), delay: 5), for: "/caller/slow.mp3")
        let dest = dir.appendingPathComponent("slow.mp3")

        let download = Task {
            try await client.downloadFile(remotePath: "/caller/slow.mp3", to: dest) { _, _ in }
        }
        try await Task.sleep(for: .milliseconds(200))
        let started = ContinuousClock.now
        download.cancel()

        await #expect(throws: (any Error).self) { try await download.value }
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }

    @Test("服务器返回 404：抛错且不留下目标文件")
    func testHTTPErrorRemovesFile() async throws {
        let client = makeClient()
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        StubURLProtocol.set(.init(status: 404), for: "/missing/a.mp3")
        let dest = dir.appendingPathComponent("a.mp3")

        await #expect(throws: (any Error).self) {
            _ = try await client.downloadFile(remotePath: "/missing/a.mp3", to: dest) { _, _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
    }
}

// MARK: - WebDAVService 下载与导入

private final class BlockingWebDAVClient: WebDAVClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _started: [String] = []
    private var _destinations: [URL] = []
    private var _cancelled = false
    let blocks: Bool

    init(blocks: Bool) { self.blocks = blocks }

    var started: [String] { lock.withLock { _started } }
    var destinations: [URL] { lock.withLock { _destinations } }
    private var cancelled: Bool { lock.withLock { _cancelled } }

    func testConnection() async throws -> Bool { true }
    func listDirectory(path: String) async throws -> [WebDAVFile] { [] }

    func downloadFile(
        remotePath: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        lock.withLock {
            _started.append(remotePath)
            _destinations.append(destination)
        }
        if blocks {
            while !cancelled && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            throw CancellationError()
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(remotePath.utf8).write(to: destination)
        return destination
    }

    func cancelDownload() async {
        lock.withLock { _cancelled = true }
    }
}

private final class FixedFactory: WebDAVClientFactory {
    let client: WebDAVClientProtocol
    init(client: WebDAVClientProtocol) { self.client = client }
    func makeClient(baseURL: URL, username: String, password: String, trustSelfSignedCert: Bool) -> WebDAVClientProtocol {
        client
    }
}

private final class AccountStore: WebDAVAccountStoring {
    func loadAccounts() -> [WebDAVAccount] { [] }
    func saveAccount(_ account: WebDAVAccount, password: String?) throws {}
    func deleteAccount(id: UUID) throws {}
    func password(for accountId: UUID) -> String? { "secret" }
    func updateLastConnected(accountId: UUID) throws {}
}

@MainActor
private final class RecordingImporter: FileImporting {
    private(set) var importedURLs: [URL]?

    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult {
        importedURLs = urls
        return ImportResult(
            successCount: urls.count, skippedDuplicateCount: 0, skippedFormatCount: 0,
            failedCount: 0, incompleteMetadataCount: 0, skippedOversizeCount: 0, details: []
        )
    }
}

private func audioFile(_ href: String) -> WebDAVFile {
    WebDAVFile(href: href, displayName: "", contentLength: 10, contentType: "audio/mpeg",
               lastModified: nil, isDirectory: false, etag: nil)
}

@Suite("WebDAVService 下载与导入")
@MainActor
struct WebDAVServiceDownloadTests {

    private struct Fixture {
        let service: WebDAVService
        let importer: RecordingImporter
        let storage: MockFileStorageProviding
    }

    private func makeFixture(client: WebDAVClientProtocol) async throws -> Fixture {
        let provider = MockSubscriptionProvider()
        provider.entitlementState = EntitlementState(
            hasLifetime: true, hasActiveSubscription: false, subscriptionExpirationDate: nil)
        let subscription = SubscriptionService(provider: provider)
        await subscription.refreshStatus()
        let importer = RecordingImporter()
        let storage = MockFileStorageProviding()
        storage.importTempURL = makeTempDir()
        let service = WebDAVService(
            accountStore: AccountStore(),
            clientFactory: FixedFactory(client: client),
            importService: importer,
            fileStorage: storage,
            subscriptionService: subscription
        )
        let account = WebDAVAccount(
            id: UUID(), displayName: "", serverURL: "https://dav.test", username: "u",
            trustSelfSignedCert: false, lastConnectedAt: nil)
        try? await service.connect(to: account)
        return Fixture(service: service, importer: importer, storage: storage)
    }

    @Test("不同目录下的同名文件下载到不同路径，导入时保留原文件名")
    func testSameNameFilesDoNotCollide() async throws {
        let client = BlockingWebDAVClient(blocks: false)
        let fixture = try await makeFixture(client: client)
        defer { try? FileManager.default.removeItem(at: fixture.storage.importTempURL) }

        let result = await fixture.service.downloadAndImport(
            files: [audioFile("/A/01.mp3"), audioFile("/B/01.mp3")]
        ) { _ in }

        #expect(result.downloadedCount == 2)
        let imported = fixture.importer.importedURLs ?? []
        #expect(imported.count == 2)
        #expect(Set(imported).count == 2)
        #expect(imported.allSatisfy { $0.lastPathComponent == "01.mp3" })
    }

    @Test("下载中取消：不再派发新下载、不导入，未完成任务标为已取消")
    func testCancelStopsDispatchAndImport() async throws {
        let client = BlockingWebDAVClient(blocks: true)
        let fixture = try await makeFixture(client: client)
        defer { try? FileManager.default.removeItem(at: fixture.storage.importTempURL) }
        let files = (1...5).map { audioFile("/music/\($0).mp3") }

        let running = Task { await fixture.service.downloadAndImport(files: files) { _ in } }
        let deadline = ContinuousClock.now + .seconds(2)
        while client.started.count < 3 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        fixture.service.cancelDownload()
        let result = await running.value

        #expect(client.started.count == 3)
        #expect(fixture.importer.importedURLs == nil)
        #expect(result.importResult == nil)
        #expect(result.errors.contains("已取消"))
        #expect(fixture.service.downloadTasks.allSatisfy { $0.error == "已取消" })
    }

    @Test("结束后删除本次临时根目录")
    func testTempRootRemoved() async throws {
        let client = BlockingWebDAVClient(blocks: false)
        let fixture = try await makeFixture(client: client)
        defer { try? FileManager.default.removeItem(at: fixture.storage.importTempURL) }

        _ = await fixture.service.downloadAndImport(files: [audioFile("/A/x.mp3")]) { _ in }

        let destination = try #require(client.destinations.first)
        let tempRoot = destination.deletingLastPathComponent().deletingLastPathComponent()
        #expect(tempRoot.lastPathComponent.hasPrefix("webdav-"))
        #expect(fixture.storage.removedItems.contains(tempRoot))
    }
}

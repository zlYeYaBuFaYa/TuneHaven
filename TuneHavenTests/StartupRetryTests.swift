import Foundation
import Testing
@testable import TuneHaven

@Suite("启动重试与日志位置")
struct StartupRetryTests {
    @Test("CoreDataStack 重复 load 不报错，已有数据仍可读")
    func loadIsIdempotent() async throws {
        let stack = try await CoreDataStack.makeInMemory()
        let repo = CoreDataSongRepository(stack: stack)
        let song = makeSong()
        try await repo.insert(song: song)

        try await stack.load()

        #expect(await repo.fetchSong(id: song.id)?.id == song.id)
    }

    @Test("日志写在 Caches，不在 Documents")
    func logsLiveInCaches() {
        let url = SandboxPathManager.logFileURL(named: "app.log")
        #expect(url.deletingLastPathComponent().standardizedFileURL == SandboxPathManager.cachesURL.standardizedFileURL)
        #expect(!url.path.hasPrefix(SandboxPathManager.documentsURL.path))
    }

    @Test("启动时删除 Documents 里的旧日志")
    func legacyLogsRemoved() throws {
        let legacy = SandboxPathManager.documentsURL.appendingPathComponent("error.log.old")
        try Data("old".utf8).write(to: legacy)

        SandboxPathManager.removeLegacyLogs()

        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }
}

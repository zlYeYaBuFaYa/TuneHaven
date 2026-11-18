import Foundation
import Testing
@testable import TuneHaven

@MainActor
@Suite("删除撤销窗口：前后台提交")
struct DeferredDeleteCommitTests {

    @Test("进后台时窗口未到期：申请后台时间，系统收回前全部提交")
    func backgroundRequestsTimeAndCommitsOnExpiration() async throws {
        let repo = MockSongRepository()
        let background = RecordingBackgroundTask()
        let service = MusicLibraryService(songRepo: repo, imageCache: MockImageCacheManaging(), backgroundTask: background)
        let id = UUID()
        _ = try await service.softDelete(songIds: [id])

        await service.handleDidEnterBackground()
        #expect(background.begun == 1)
        #expect(repo.committedSongIds.isEmpty)

        background.expire()
        await waitUntil { background.ended == [1] }
        #expect(repo.committedSongIds == [[id]])
    }

    @Test("进后台时已到期：立即提交，不申请后台时间")
    func backgroundCommitsExpiredImmediately() async throws {
        let repo = MockSongRepository()
        repo.softDeleteWindow = -1
        let background = RecordingBackgroundTask()
        let service = MusicLibraryService(songRepo: repo, imageCache: MockImageCacheManaging(), backgroundTask: background)
        let id = UUID()
        _ = try await service.softDelete(songIds: [id])

        await service.handleDidEnterBackground()

        #expect(repo.committedSongIds == [[id]])
        #expect(background.begun == 0)
    }

    @Test("回前台只补提交已到期的，且每个只提交一次")
    func foregroundCommitsOnlyExpiredOnce() async throws {
        let repo = MockSongRepository()
        let service = MusicLibraryService(songRepo: repo, imageCache: MockImageCacheManaging())
        let fresh = try await service.softDelete(songIds: [UUID()])

        await service.commitExpiredDeletes()
        #expect(repo.committedSongIds.isEmpty)

        await service.commitExpiredDeletes(now: fresh.expiresAt)
        await service.commitExpiredDeletes(now: fresh.expiresAt)
        #expect(repo.committedSongIds == [fresh.songIds])
    }

    @Test("撤销后结束后台时间；已提交的不能再撤销")
    func undoEndsBackgroundTaskAndRejectsCommitted() async throws {
        let repo = MockSongRepository()
        let background = RecordingBackgroundTask()
        let service = MusicLibraryService(songRepo: repo, imageCache: MockImageCacheManaging(), backgroundTask: background)
        let undone = try await service.softDelete(songIds: [UUID()])

        await service.handleDidEnterBackground()
        try await service.undoDelete(token: undone)
        #expect(background.ended == [1])
        #expect(repo.undoneSongIds == [undone.songIds])

        let committed = try await service.softDelete(songIds: [UUID()])
        await service.commitExpiredDeletes(now: committed.expiresAt)
        await #expect(throws: AppError.self) {
            try await service.undoDelete(token: committed)
        }
        #expect(repo.undoneSongIds == [undone.songIds])
    }
}

private final class RecordingBackgroundTask: BackgroundTaskProviding {
    private(set) var begun = 0
    private(set) var ended: [UInt] = []
    private var expirationHandler: (@Sendable () -> Void)?

    func beginTask(expirationHandler: (@Sendable () -> Void)?) -> UInt {
        begun += 1
        self.expirationHandler = expirationHandler
        return UInt(begun)
    }

    func endTask(_ identifier: UInt) { ended.append(identifier) }

    func expire() { expirationHandler?() }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

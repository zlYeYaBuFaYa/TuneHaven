import Testing
import Foundation
@testable import TuneHaven

// MARK: - Test Helpers

private func makeSong(
    id: UUID = UUID(),
    title: String = "Test Song",
    artist: String = "Test Artist",
    album: String = "Test Album",
    duration: TimeInterval = 180,
    fileHash: String = UUID().uuidString
) -> Song {
    Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        fileHash: fileHash,
        fileRelativePath: "\(fileHash).mp3",
        coverImagePath: nil,
        lyricsPath: nil,
        lyricsSource: nil,
        metadata: Metadata(
            format: "mp3",
            sampleRate: 44100,
            bitRate: 320,
            channels: 2,
            encoder: nil,
            trackNumber: nil,
            year: 2024,
            genre: nil
        ),
        importDate: Date(),
        fileSize: 1024 * 1024,
        playCount: 0,
        isFavorite: false,
        favoriteDate: nil,
        lastPlayedDate: nil
    )
}

// MARK: - #1 UndoToken.MovedFile 路径分离测试

@Suite("P0 #1: UndoToken 路径修复")
struct UndoTokenPathTests {

    @Test("MovedFile 分别保存临时路径和原始路径")
    func movedFileKeepsBothPaths() {
        let moved = UndoToken.MovedFile(
            tempPath: "pending_delete/abc123.mp3",
            originalRelativePath: "Music/夜曲.mp3"
        )
        #expect(moved.tempPath == "pending_delete/abc123.mp3")
        #expect(moved.originalRelativePath == "Music/夜曲.mp3")
    }

    @Test("临时路径和原始路径不相同")
    func pathsAreDifferent() {
        let moved = UndoToken.MovedFile(
            tempPath: "pending_delete/hash_夜曲.mp3",
            originalRelativePath: "Music/夜曲.mp3"
        )
        #expect(moved.tempPath != moved.originalRelativePath)
    }

    @Test("UndoToken 使用 movedFiles 替代 tempFilePaths")
    func tokenUsesMovedFiles() {
        let files = [
            UndoToken.MovedFile(tempPath: "tmp/a.mp3", originalRelativePath: "Music/a.mp3"),
            UndoToken.MovedFile(tempPath: "tmp/b.mp3", originalRelativePath: "Music/b.mp3"),
        ]
        let token = UndoToken(songIds: [UUID(), UUID()], movedFiles: files, expiresAt: Date().addingTimeInterval(30))
        #expect(token.movedFiles.count == 2)
        #expect(token.songIds.count == 2)
    }

    @Test("空 movedFiles 表示没有文件需要移动（引用计数未归零）")
    func emptyMovedFilesIsValid() {
        let token = UndoToken(songIds: [UUID()], movedFiles: [], expiresAt: Date().addingTimeInterval(30))
        #expect(token.movedFiles.isEmpty)
        #expect(token.songIds.count == 1)
    }
}

// MARK: - #2 CoreDataStack.performBackground 回滚测试

@Suite("P0 #2: performBackground 异常回滚")
struct PerformBackgroundRollbackTests {

    @Test("performBackground 在 block 抛出异常时应抛出错误")
    func throwsOnBlockError() async {
        let stack = CoreDataStack.shared

        enum TestError: Error { case intentional }

        do {
            try await stack.performBackground { _ in
                throw TestError.intentional
            }
            Issue.record("应当抛出异常")
        } catch {
            #expect(error is TestError)
        }
    }

    @Test("performBackground 成功时返回正确结果")
    func returnsResultOnSuccess() async throws {
        let stack = CoreDataStack.shared

        let result = try await stack.performBackground { _ in
            return 42
        }
        #expect(result == 42)
    }
}

// MARK: - #3 歌单播放队列构建测试

@Suite("P0 #3: PlayQueueService 队列替换")
struct PlaylistQueueTests {

    @Test("replaceQueue 应加载全部歌曲而非单首")
    @MainActor
    func replaceQueueLoadsAllSongs() {
        let service = PlayQueueService()
        let songs = (0..<5).map { i in makeSong(title: "Song \(i)") }

        service.replaceQueue(with: songs, startAt: 2)

        #expect(service.queue.count == 5)
        #expect(service.currentIndex == 2)
        #expect(service.queue[2].song.title == "Song 2")
    }

    @Test("从歌单播放时队列应包含歌单所有歌曲")
    @MainActor
    func queueContainsAllPlaylistSongs() {
        let service = PlayQueueService()
        let playlistSongs = [
            makeSong(title: "A"),
            makeSong(title: "B"),
            makeSong(title: "C"),
        ]

        service.replaceQueue(with: playlistSongs, startAt: 1)

        #expect(service.queue.count == 3)
        #expect(service.queue[0].song.title == "A")
        #expect(service.queue[1].song.title == "B")
        #expect(service.queue[2].song.title == "C")
        #expect(service.currentIndex == 1)
    }

    @Test("单首歌播放时队列只有一首（.queue context）")
    @MainActor
    func singleSongQueue() {
        let service = PlayQueueService()
        let song = makeSong(title: "Solo")

        service.replaceQueue(with: [song], startAt: 0)

        #expect(service.queue.count == 1)
        #expect(service.currentIndex == 0)
    }
}

import Testing
@testable import music_demo

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

// MARK: - PlayQueueService Tests

@Suite("PlayQueueService Tests")
struct PlayQueueServiceTests {

    // MARK: replaceQueue

    @Test("replaceQueue 替换整个队列并设置起始索引", .serialized)
    @MainActor func testReplaceQueue() {
        let service = PlayQueueService()
        let songs = (1...5).map { makeSong(title: "歌曲\($0)") }
        service.replaceQueue(with: songs, startAt: 2)

        #expect(service.queue.count == 5)
        #expect(service.currentIndex == 2)
        #expect(service.currentItem?.song.title == "歌曲3")
    }

    @Test("replaceQueue 空列表时 currentIndex 为 nil", .serialized)
    @MainActor func testReplaceQueueEmpty() {
        let service = PlayQueueService()
        service.replaceQueue(with: [], startAt: 0)

        #expect(service.queue.isEmpty)
        #expect(service.currentIndex == nil)
    }

    @Test("replaceQueue 越界索引回退到 0", .serialized)
    @MainActor func testReplaceQueueOutOfBoundsIndex() {
        let service = PlayQueueService()
        let songs = [makeSong(), makeSong()]
        service.replaceQueue(with: songs, startAt: 10)

        #expect(service.currentIndex == 0)
    }

    // MARK: appendToQueue

    @Test("appendToQueue 正常追加歌曲", .serialized)
    @MainActor func testAppendToQueue() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B")]
        let result = service.appendToQueue(songs)

        #expect(result == .success)
        #expect(service.queue.count == 2)
    }

    @Test("appendToQueue 超出 999 首上限时返回 queueFull", .serialized)
    @MainActor func testAppendToQueueFull() {
        let service = PlayQueueService()
        // 先填满 999 首
        let initialSongs = (0..<999).map { makeSong(title: "S\($0)") }
        _ = service.appendToQueue(initialSongs)

        let result = service.appendToQueue([makeSong(title: "Overflow")])

        switch result {
        case .queueFull(let count):
            #expect(count == 999)
        case .success:
            Issue.record("Expected queueFull but got success")
        }
    }

    @Test("appendToQueue 恰好到达 999 首返回 success", .serialized)
    @MainActor func testAppendToQueueExactLimit() {
        let service = PlayQueueService()
        let songs = (0..<999).map { makeSong(title: "S\($0)") }
        let result = service.appendToQueue(songs)

        #expect(result == .success)
        #expect(service.count == 999)
    }

    // MARK: insertNext

    @Test("insertNext 在当前歌曲后插入", .serialized)
    @MainActor func testInsertNext() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        let newSong = makeSong(title: "B")
        let result = service.insertNext(newSong)

        #expect(result == .success)
        #expect(service.queue.count == 3)
        #expect(service.queue[1].song.title == "B")
        #expect(service.queue[2].song.title == "C")
    }

    @Test("insertNext 队列为空时插入到位置 0", .serialized)
    @MainActor func testInsertNextEmptyQueue() {
        let service = PlayQueueService()
        let result = service.insertNext(makeSong(title: "OnlyOne"))

        #expect(result == .success)
        #expect(service.queue.count == 1)
        #expect(service.queue[0].song.title == "OnlyOne")
    }

    @Test("insertNext 队列满时返回 queueFull", .serialized)
    @MainActor func testInsertNextQueueFull() {
        let service = PlayQueueService()
        let songs = (0..<999).map { makeSong(title: "S\($0)") }
        _ = service.appendToQueue(songs)

        let result = service.insertNext(makeSong(title: "Overflow"))

        switch result {
        case .queueFull:
            break // expected
        case .success:
            Issue.record("Expected queueFull")
        }
    }

    // MARK: removeFromQueue

    @Test("removeFromQueue 删除队列中的歌曲", .serialized)
    @MainActor func testRemoveFromQueue() {
        let service = PlayQueueService()
        let songs = (1...4).map { makeSong(title: "S\($0)") }
        service.replaceQueue(with: songs, startAt: 2)

        service.removeFromQueue(at: IndexSet([0, 1]))

        #expect(service.queue.count == 2)
        #expect(service.queue[0].song.title == "S3")
        #expect(service.queue[1].song.title == "S4")
    }

    @Test("removeFromQueue 删除当前歌曲时索引调整", .serialized)
    @MainActor func testRemoveCurrentFromQueue() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 1) // currentIndex = 1 (B)

        service.removeFromQueue(at: IndexSet([1]))

        #expect(service.queue.count == 2)
        #expect(service.currentIndex == 1) // 调整到下一首 C
    }

    @Test("removeFromQueue 删除当前前面的歌曲时索引减少", .serialized)
    @MainActor func testRemoveSongBeforeCurrent() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 2) // currentIndex = 2 (C)

        service.removeFromQueue(at: IndexSet([0])) // 删除 A

        #expect(service.currentIndex == 1) // C 的新索引是 1
    }

    // MARK: clearQueue

    @Test("clearQueue 清空队列和索引", .serialized)
    @MainActor func testClearQueue() {
        let service = PlayQueueService()
        service.replaceQueue(with: [makeSong(), makeSong()], startAt: 0)
        service.clearQueue()

        #expect(service.queue.isEmpty)
        #expect(service.currentIndex == nil)
    }

    // MARK: nextSong - Sequential

    @Test("nextSong(sequential) 返回下一首未播放歌曲", .serialized)
    @MainActor func testNextSongSequential() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        let next = service.nextSong(for: .sequential, dislikes: [:])
        #expect(next?.song.title == "B")
    }

    @Test("nextSong(sequential) 队列末尾时返回 nil", .serialized)
    @MainActor func testNextSongSequentialAtEnd() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B")]
        service.replaceQueue(with: songs, startAt: 0)
        service.markCurrentAsPlayed()
        service.setCurrentIndex(to: 1)
        service.markCurrentAsPlayed()

        let next = service.nextSong(for: .sequential, dislikes: [:])
        #expect(next == nil)
    }

    @Test("nextSong(sequential) 跳过已播放的歌曲", .serialized)
    @MainActor func testNextSongSequentialSkipsPlayed() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        // 手动标记 B（索引1）为已播放
        service.setCurrentIndex(to: 1)
        service.markCurrentAsPlayed()
        service.setCurrentIndex(to: 0)

        let next = service.nextSong(for: .sequential, dislikes: [:])
        // 下一首应该是 C（跳过已播放的 B）
        #expect(next?.song.title == "C")
    }

    // MARK: nextSong - RepeatOne

    @Test("nextSong(repeatOne) 返回当前歌曲", .serialized)
    @MainActor func testNextSongRepeatOne() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B")]
        service.replaceQueue(with: songs, startAt: 0)

        let next = service.nextSong(for: .repeatOne, dislikes: [:])
        #expect(next?.song.title == "A")
    }

    // MARK: nextSong - RepeatAll

    @Test("nextSong(repeatAll) 正常返回下一首", .serialized)
    @MainActor func testNextSongRepeatAll() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        let next = service.nextSong(for: .repeatAll, dislikes: [:])
        #expect(next?.song.title == "B")
    }

    @Test("nextSong(repeatAll) 末尾时重置已播放标记并返回第一首", .serialized)
    @MainActor func testNextSongRepeatAllLoops() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B")]
        service.replaceQueue(with: songs, startAt: 0)

        // 将所有歌曲标记为已播放
        service.setCurrentIndex(to: 0)
        service.markCurrentAsPlayed()
        service.setCurrentIndex(to: 1)
        service.markCurrentAsPlayed()

        let next = service.nextSong(for: .repeatAll, dislikes: [:])
        #expect(next?.song.title == "A") // 重置后从第一首开始
        // 验证已播放标记已重置
        #expect(service.queue.allSatisfy { !$0.isPlayed })
    }

    // MARK: nextSong - Shuffle

    @Test("nextSong(shuffle) 从未播放歌曲中随机选择", .serialized)
    @MainActor func testNextSongShuffle() {
        let service = PlayQueueService()
        let songs = (1...10).map { makeSong(title: "S\($0)") }
        service.replaceQueue(with: songs, startAt: 0)

        let next = service.nextSong(for: .shuffle, dislikes: [:])
        #expect(next != nil)
        #expect(!next!.isPlayed)
    }

    @Test("nextSong(shuffle) 所有歌曲已播放时返回 nil", .serialized)
    @MainActor func testNextSongShuffleAllPlayed() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B")]
        service.replaceQueue(with: songs, startAt: 0)

        // 标记所有歌曲为已播放
        for i in 0..<service.queue.count {
            service.setCurrentIndex(to: i)
            service.markCurrentAsPlayed()
        }

        let next = service.nextSong(for: .shuffle, dislikes: [:])
        #expect(next == nil)
    }

    @Test("nextSong(shuffle) dislikeCount 高的歌曲概率降低", .serialized)
    @MainActor func testNextSongShuffleDislikeWeighting() {
        let service = PlayQueueService()
        let dislikedId = UUID()
        let normalId = UUID()
        let songs = [
            makeSong(id: dislikedId, title: "Disliked"),
            makeSong(id: normalId, title: "Normal")
        ]
        service.replaceQueue(with: songs, startAt: 0)

        let dislikes = [dislikedId.uuidString: 5]
        var dislikedCount = 0
        var normalCount = 0

        // 运行多次，验证不喜欢的歌曲被选中的概率明显低于正常歌曲
        // 重置标记并重新统计
        for _ in 0..<100 {
            service.resetAllPlayedMarks()
            if let next = service.nextSong(for: .shuffle, dislikes: dislikes) {
                if next.song.title == "Disliked" { dislikedCount += 1 }
                else { normalCount += 1 }
            }
        }
        // dislikeCount=5 时权重为 1/6，正常权重为 1，所以 Normal 应占 ~85%
        #expect(normalCount > dislikedCount)
    }

    // MARK: previousSong

    @Test("previousSong 返回上一首歌曲", .serialized)
    @MainActor func testPreviousSong() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 2)

        let previous = service.previousSong()
        #expect(previous?.song.title == "B")
    }

    @Test("previousSong 在第一首时返回 nil", .serialized)
    @MainActor func testPreviousSongAtFirst() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B")]
        service.replaceQueue(with: songs, startAt: 0)

        let previous = service.previousSong()
        #expect(previous == nil)
    }

    // MARK: markCurrentAsPlayed

    @Test("markCurrentAsPlayed 标记当前歌曲为已播放", .serialized)
    @MainActor func testMarkCurrentAsPlayed() {
        let service = PlayQueueService()
        service.replaceQueue(with: [makeSong()], startAt: 0)

        #expect(service.currentItem?.isPlayed == false)
        service.markCurrentAsPlayed()
        #expect(service.currentItem?.isPlayed == true)
    }

    @Test("markCurrentAsPlayed 无当前歌曲时无效果", .serialized)
    @MainActor func testMarkCurrentAsPlayedNoCurrent() {
        let service = PlayQueueService()
        // 不设置队列，直接调用
        service.markCurrentAsPlayed() // 不应崩溃
        #expect(service.currentIndex == nil)
    }

    // MARK: resetAllPlayedMarks

    @Test("resetAllPlayedMarks 重置所有已播放标记", .serialized)
    @MainActor func testResetAllPlayedMarks() {
        let service = PlayQueueService()
        let songs = (1...3).map { makeSong(title: "S\($0)") }
        service.replaceQueue(with: songs, startAt: 0)

        for i in 0..<3 {
            service.setCurrentIndex(to: i)
            service.markCurrentAsPlayed()
        }
        #expect(service.queue.allSatisfy { $0.isPlayed })

        service.resetAllPlayedMarks()
        #expect(service.queue.allSatisfy { !$0.isPlayed })
    }

    // MARK: moveInQueue

    @Test("moveInQueue 调整歌曲顺序", .serialized)
    @MainActor func testMoveInQueue() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        service.moveInQueue(from: IndexSet([2]), to: 0) // 将 C 移到最前

        #expect(service.queue[0].song.title == "C")
        #expect(service.queue[1].song.title == "A")
        #expect(service.queue[2].song.title == "B")
    }

    // MARK: advanceToCurrent

    @Test("advanceToCurrent 根据 QueueItem 更新 currentIndex", .serialized)
    @MainActor func testAdvanceToCurrent() {
        let service = PlayQueueService()
        let songs = [makeSong(title: "A"), makeSong(title: "B"), makeSong(title: "C")]
        service.replaceQueue(with: songs, startAt: 0)

        let targetItem = service.queue[2]
        service.advanceToCurrent(targetItem)

        #expect(service.currentIndex == 2)
    }

    // MARK: count

    @Test("count 返回队列长度", .serialized)
    @MainActor func testCount() {
        let service = PlayQueueService()
        #expect(service.count == 0)

        let songs = (1...5).map { makeSong(title: "S\($0)") }
        _ = service.appendToQueue(songs)
        #expect(service.count == 5)
    }
}

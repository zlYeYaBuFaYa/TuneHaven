import Foundation
import Combine

@MainActor
final class PlayQueueService: ObservableObject {
    private let log = AppLogger.shared

    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var currentIndex: Int? = nil

    var currentItem: QueueItem? {
        guard let idx = currentIndex, queue.indices.contains(idx) else { return nil }
        return queue[idx]
    }

    var count: Int { queue.count }

    func replaceQueue(with songs: [Song], startAt index: Int) {
        log.info("替换播放队列: \(songs.count) 首，起始索引=\(index)")
        queue = songs.map { QueueItem(song: $0) }
        currentIndex = queue.indices.contains(index) ? index : (queue.isEmpty ? nil : 0)
    }

    func appendToQueue(_ songs: [Song]) -> QueueAddResult {
        guard queue.count + songs.count <= PlayQueueConstants.maxCount else {
            log.info("播放队列已满，当前 \(queue.count) 首")
            return .queueFull(currentCount: queue.count)
        }
        queue.append(contentsOf: songs.map { QueueItem(song: $0) })
        return .success
    }

    func insertNext(_ song: Song) -> QueueAddResult {
        guard queue.count < PlayQueueConstants.maxCount else {
            return .queueFull(currentCount: queue.count)
        }
        let insertAt = (currentIndex ?? -1) + 1
        queue.insert(QueueItem(song: song), at: min(insertAt, queue.count))
        return .success
    }

    func removeFromQueue(at indices: IndexSet) {
        queue.remove(atOffsets: indices)
        if let idx = currentIndex {
            if indices.contains(idx) {
                currentIndex = queue.isEmpty ? nil : min(idx, queue.count - 1)
            } else {
                let removed = indices.filter { $0 < idx }.count
                currentIndex = idx - removed
            }
        }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        let currentId = currentItem?.id
        queue.move(fromOffsets: source, toOffset: destination)
        if let currentId {
            currentIndex = queue.firstIndex(where: { $0.id == currentId })
        }
    }

    func clearQueue() {
        log.info("清空播放队列")
        queue = []
        currentIndex = nil
    }

    /// 将当前队列保存为新歌单（TDD Section 3.6）
    @discardableResult
    func saveQueueAsPlaylist(name: String, playlistService: PlaylistService) async throws -> Playlist {
        let songIds = queue.map { $0.song.id }
        let playlist = try await playlistService.createPlaylist(name: name, description: nil)
        try await playlistService.addSongs(songIds, to: playlist.id)
        return playlist
    }

    func nextSong(for mode: PlayMode, dislikes: [String: Int]) -> QueueItem? {
        switch mode {
        case .sequential:
            return nextUnplayed(from: (currentIndex ?? -1) + 1)
        case .repeatOne:
            return currentItem
        case .repeatAll:
            if let item = nextUnplayed(from: (currentIndex ?? -1) + 1) { return item }
            guard !queue.isEmpty else { return nil }
            resetAllPlayedMarks()
            return queue.first
        case .shuffle:
            return weightedRandom(dislikes: dislikes)
        }
    }

    func previousSong() -> QueueItem? {
        guard let idx = currentIndex, idx > 0 else { return nil }
        return queue[idx - 1]
    }

    func markCurrentAsPlayed() {
        guard let idx = currentIndex else { return }
        queue[idx].isPlayed = true
    }

    func resetAllPlayedMarks() {
        for i in queue.indices { queue[i].isPlayed = false }
    }

    func setCurrentIndex(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
    }

    func advanceToCurrent(_ item: QueueItem) {
        if let idx = queue.firstIndex(where: { $0.id == item.id }) {
            currentIndex = idx
        }
    }

    private func nextUnplayed(from start: Int) -> QueueItem? {
        for i in start..<queue.count {
            if !queue[i].isPlayed { return queue[i] }
        }
        return nil
    }

    private func weightedRandom(dislikes: [String: Int]) -> QueueItem? {
        let candidates = queue.filter { !$0.isPlayed }
        guard !candidates.isEmpty else { return nil }
        let weights = candidates.map { item -> Double in
            let count = dislikes[item.song.id.uuidString] ?? 0
            return 1.0 / (1.0 + Double(count))
        }
        let total = weights.reduce(0, +)
        var random = Double.random(in: 0..<total)
        for (item, weight) in zip(candidates, weights) {
            random -= weight
            if random <= 0 { return item }
        }
        return candidates.last
    }
}

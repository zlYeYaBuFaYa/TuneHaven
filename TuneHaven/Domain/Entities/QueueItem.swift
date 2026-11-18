import Foundation

struct QueueItem: Identifiable, Hashable {
    let id: UUID
    /// 歌曲信息被编辑后会就地替换，队列项 id 不变
    var song: Song
    var isPlayed: Bool
    let addedAt: Date

    init(song: Song, isPlayed: Bool = false) {
        self.id = UUID()
        self.song = song
        self.isPlayed = isPlayed
        self.addedAt = Date()
    }

}

enum QueueAddResult: Equatable {
    case success
    case queueFull(currentCount: Int)
}

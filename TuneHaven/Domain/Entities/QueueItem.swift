import Foundation

struct QueueItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let song: Song
    var isPlayed: Bool
    let addedAt: Date

    init(id: UUID = UUID(), song: Song, isPlayed: Bool = false, addedAt: Date = Date()) {
        self.id = id
        self.song = song
        self.isPlayed = isPlayed
        self.addedAt = addedAt
    }

}

enum QueueAddResult: Equatable {
    case success
    case queueFull(currentCount: Int)
}

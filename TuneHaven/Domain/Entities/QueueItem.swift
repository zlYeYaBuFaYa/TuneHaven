import Foundation

struct QueueItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let song: Song
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

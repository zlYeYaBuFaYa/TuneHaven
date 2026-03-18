import Foundation

struct QueueItem: Identifiable, Hashable {
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

    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum PlayQueueConstants {
    static let maxCount = 999
    static let persist = false
    static let removePlayed = false
    static let markAsPlayed = true
}

enum QueueAddResult {
    case success
    case queueFull(currentCount: Int)
}

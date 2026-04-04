import Foundation

struct PlaylistGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var sortOrder: Int

    static func == (lhs: PlaylistGroup, rhs: PlaylistGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PlaylistGroupDetail: Identifiable, Sendable {
    let id: UUID
    let name: String
    let playlists: [Playlist]
    let totalSongCount: Int
}

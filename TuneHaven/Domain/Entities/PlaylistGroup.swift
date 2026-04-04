import Foundation

struct PlaylistGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var sortOrder: Int

}

struct PlaylistGroupDetail: Identifiable, Sendable {
    let id: UUID
    let name: String
    let playlists: [Playlist]
    let totalSongCount: Int
}

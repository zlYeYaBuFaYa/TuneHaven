import Foundation

struct Playlist: Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    var coverImagePath: String?
    var autoCoverHash: String?
    var isSystem: Bool
    var systemType: SystemPlaylistType
    var songCount: Int
    var groupId: UUID?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SystemPlaylistType: Int16 {
    case normal = 0
    case favorites = 1
    case recentlyPlayed = 2
}

enum SystemPlaylistName {
    static let favorites = "我喜欢"
    static let recentlyPlayed = "最近播放"
}

struct PlaylistDetail {
    let playlist: Playlist
    let songs: [Song]
}

struct PagedResult<T> {
    let items: [T]
    let totalCount: Int
    let currentPage: Int
    let hasMore: Bool
}

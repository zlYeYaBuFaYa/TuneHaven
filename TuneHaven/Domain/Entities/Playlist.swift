import Foundation

struct Playlist: Identifiable, Hashable, Sendable {
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

}

enum SystemPlaylistType: Int16 {
    case normal = 0
    case favorites = 1
    case recentlyPlayed = 2
}

/// 系统歌单内部标识名称，用于创建和查找系统歌单，不直接展示给用户。
enum SystemPlaylistName {
    static let favorites = "我喜欢"
    static let recentlyPlayed = "最近播放"
}

struct PlaylistDetail: Identifiable, Sendable {
    let playlist: Playlist
    let songs: [Song]

    var id: UUID { playlist.id }
}

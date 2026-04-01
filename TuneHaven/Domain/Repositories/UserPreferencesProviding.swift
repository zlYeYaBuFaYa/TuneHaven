import Foundation

// TODO: 字典键（songDislikes/perSongSpeeds/lyricsCooldown）当前为裸 String（UUID），
// 后续考虑引入 SongKey 类型安全封装以消除 .uuidString 散落
protocol UserPreferencesProviding: AnyObject {
    var playMode: PlayMode { get set }
    var playbackSpeed: Float { get set }
    var speedMemoryMode: SpeedMemoryMode { get }
    var autoMatchLyrics: Bool { get }
    var recentPlayRange: Int { get }
    var lastPlayedSongId: String? { get set }
    var songDislikes: [String: Int] { get set }
    var perSongSpeeds: [String: Float] { get set }
    var lyricsCooldown: [String: Double] { get set }
}

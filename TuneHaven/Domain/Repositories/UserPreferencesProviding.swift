import Foundation

protocol UserPreferencesProviding: AnyObject {
    var playMode: PlayMode { get set }
    var playbackSpeed: Float { get set }
    var speedMemoryMode: SpeedMemoryMode { get }
    var autoMatchLyrics: Bool { get }
    var lastPlayedSongId: String? { get set }
    var songDislikes: [String: Int] { get set }
    var perSongSpeeds: [String: Float] { get set }
    var lyricsCooldown: [String: Double] { get set }
}

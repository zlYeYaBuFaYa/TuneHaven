import Foundation

protocol UserPreferencesProviding: AnyObject {
    var playMode: Int { get set }
    var playbackSpeed: Float { get set }
    var speedMemoryMode: Int { get }
    var autoMatchLyrics: Bool { get }
    var lastPlayedSongId: String? { get set }
    var songDislikes: [String: Int] { get set }
    var perSongSpeeds: [String: Float] { get set }
    var lyricsCooldown: [String: Double] { get set }
}

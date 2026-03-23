import Foundation

final class UserPreferencesStore: UserPreferencesProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var playMode: Int {
        get { defaults.integer(forKey: AppStorageKey.playMode) }
        set { defaults.set(newValue, forKey: AppStorageKey.playMode) }
    }

    var playbackSpeed: Float {
        get {
            let v = defaults.float(forKey: AppStorageKey.playbackSpeed)
            return v == 0 ? 1.0 : v
        }
        set { defaults.set(newValue, forKey: AppStorageKey.playbackSpeed) }
    }

    var speedMemoryMode: Int {
        defaults.integer(forKey: AppStorageKey.speedMemoryMode)
    }

    var autoMatchLyrics: Bool {
        defaults.object(forKey: AppStorageKey.autoMatchLyrics) as? Bool ?? true
    }

    var lastPlayedSongId: String? {
        get { defaults.string(forKey: AppStorageKey.lastPlayedSongId) }
        set { defaults.set(newValue, forKey: AppStorageKey.lastPlayedSongId) }
    }

    var songDislikes: [String: Int] {
        get { defaults.dictionary(forKey: AppStorageKey.songDislikes) as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: AppStorageKey.songDislikes) }
    }

    var perSongSpeeds: [String: Float] {
        get { defaults.dictionary(forKey: AppStorageKey.perSongSpeeds) as? [String: Float] ?? [:] }
        set { defaults.set(newValue, forKey: AppStorageKey.perSongSpeeds) }
    }

    private static let cooldownKey = "lyrics_match_cooldown"

    var lyricsCooldown: [String: Double] {
        get { defaults.dictionary(forKey: Self.cooldownKey) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: Self.cooldownKey) }
    }
}

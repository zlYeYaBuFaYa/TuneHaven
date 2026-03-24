import Foundation

final class UserPreferencesStore: UserPreferencesProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var playMode: PlayMode {
        get { PlayMode(rawValue: defaults.integer(forKey: AppStorageKey.playMode)) ?? .sequential }
        set { defaults.set(newValue.rawValue, forKey: AppStorageKey.playMode) }
    }

    var playbackSpeed: Float {
        get {
            let v = defaults.float(forKey: AppStorageKey.playbackSpeed)
            return v == 0 ? 1.0 : v
        }
        set { defaults.set(newValue, forKey: AppStorageKey.playbackSpeed) }
    }

    var speedMemoryMode: SpeedMemoryMode {
        SpeedMemoryMode(rawValue: defaults.integer(forKey: AppStorageKey.speedMemoryMode)) ?? .global
    }

    var autoMatchLyrics: Bool {
        defaults.object(forKey: AppStorageKey.autoMatchLyrics) as? Bool ?? true
    }

    var recentPlayRange: Int {
        let v = defaults.integer(forKey: AppStorageKey.recentPlayRange)
        return v == 0 && defaults.object(forKey: AppStorageKey.recentPlayRange) == nil ? 7 : v
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

    var lyricsCooldown: [String: Double] {
        get { defaults.dictionary(forKey: AppStorageKey.lyricsCooldown) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: AppStorageKey.lyricsCooldown) }
    }
}

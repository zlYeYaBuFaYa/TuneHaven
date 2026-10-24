import Foundation

enum BackupPreferenceStore {
    static func read(from defaults: UserDefaults) -> BackupPreferences {
        let lyrics: Bool?
        if defaults.object(forKey: AppStorageKey.lyricsPreferSimplified) == nil {
            lyrics = nil
        } else {
            lyrics = defaults.bool(forKey: AppStorageKey.lyricsPreferSimplified)
        }
        let playMode: Int? = defaults.object(forKey: AppStorageKey.playMode) == nil
            ? nil
            : defaults.integer(forKey: AppStorageKey.playMode)
        let speed: Int? = defaults.object(forKey: AppStorageKey.speedMemoryMode) == nil
            ? nil
            : defaults.integer(forKey: AppStorageKey.speedMemoryMode)
        return BackupPreferences(
            themeStyle: defaults.string(forKey: AppStorageKey.themeStyle),
            playMode: playMode,
            speedMemoryMode: speed,
            lyricsPreferSimplified: lyrics
        )
    }

    /// 只写备份允许的四个键，不删除、不改写订阅、钥匙串或其它偏好。
    static func write(_ preferences: BackupPreferences, to defaults: UserDefaults) {
        if let theme = preferences.themeStyle {
            defaults.set(theme, forKey: AppStorageKey.themeStyle)
        }
        if let playMode = preferences.playMode {
            defaults.set(playMode, forKey: AppStorageKey.playMode)
        }
        if let speed = preferences.speedMemoryMode {
            defaults.set(speed, forKey: AppStorageKey.speedMemoryMode)
        }
        if let lyrics = preferences.lyricsPreferSimplified {
            defaults.set(lyrics, forKey: AppStorageKey.lyricsPreferSimplified)
        }
    }
}

import Foundation

enum AppStorageKey {
    static let playMode = "play_mode"
    static let playbackSpeed = "playback_speed"
    static let speedMemoryMode = "speed_memory_mode"
    static let perSongSpeeds = "per_song_speeds"
    static let songDislikes = "song_dislikes"
    static let lastPlayedSongId = "last_played_song_id"
    static let colorMode = "color_mode"
    static let themeStyle = "theme_style"
    static let useCustomWallpaper = "use_custom_wallpaper"
    static let recentPlayRange = "recent_play_range"
    static let wifiPasswordEnabled = "wifi_password_enabled"
    static let sleepTimerNotification = "sleep_timer_notification"
    static let cacheLimitMB = "cache_limit_mb"
    static let autoMatchLyrics = "auto_match_lyrics"
    /// `true`：歌词以简体显示；`false`：按原文显示（含繁体）。
    static let lyricsPreferSimplified = "lyrics_simplified"
    static let hasCompletedOnboarding = "has_completed_onboarding"
    static let songSortOption = "song_sort_option"
    static let songSortAscending = "song_sort_ascending"
}

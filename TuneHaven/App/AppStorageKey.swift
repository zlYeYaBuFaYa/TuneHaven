import Foundation

enum AppStorageKey {
    static let playMode = "play_mode"
    static let playbackSpeed = "playback_speed"
    static let speedMemoryMode = "speed_memory_mode"
    static let perSongSpeeds = "per_song_speeds"
    static let songDislikes = "song_dislikes"
    static let lastPlayedSongId = "last_played_song_id"
    static let themeStyle = "theme_style"
    static let useCustomWallpaper = "use_custom_wallpaper"
    static let recentPlayRange = "recent_play_range"
    static let wifiPasswordEnabled = "wifi_password_enabled"
    static let sleepTimerNotification = "sleep_timer_notification"
    static let autoMatchLyrics = "auto_match_lyrics"
    /// `true`：歌词以简体显示；`false`：按原文显示（含繁体）。
    static let lyricsPreferSimplified = "lyrics_simplified"
    static let hasCompletedOnboarding = "has_completed_onboarding"
    static let songSortOption = "song_sort_option"
    static let songSortAscending = "song_sort_ascending"
    /// 播放器封面样式：auto（晴屿用唱片，其他方形）、square、disc
    static let playerCoverStyle = "player_cover_style"
    static let lyricsCooldown = "lyrics_match_cooldown"
    /// App 首次启动日期（AppTransaction 获取失败时的兜底），Keychain 里另存一份
    static let appFirstLaunchDate = "app_first_launch_date"
    /// 已校验的 AppTransaction 首次下载日期
    static let verifiedOriginalPurchaseDate = "app_verified_original_purchase_date"
    /// 上次解析出的购买权益，启动时先用它，不等 StoreKit
    static let cachedEntitlements = "subscription_cached_entitlements"
}

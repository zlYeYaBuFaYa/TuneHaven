#if DEBUG
import Foundation

/// 仅调试构建：启动时从环境变量 `TUNEHAVEN_SEED_DIR` 指定的目录导入音频，
/// 用于在模拟器里检查 UI 重做的页面。走正常导入流程，曲库已有歌曲时不重复导入。
///
/// 用法：`SIMCTL_CHILD_TUNEHAVEN_SEED_DIR=/path/to/dir xcrun simctl launch <udid> <bundle id>`
@MainActor
enum DebugLibrarySeeder {
    static func seedIfRequested(
        importService: ImportService,
        libraryService: MusicLibraryService,
        playlistService: PlaylistService
    ) async {
        guard let dir = ProcessInfo.processInfo.environment["TUNEHAVEN_SEED_DIR"], !dir.isEmpty,
              libraryService.songs.isEmpty else { return }
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir, isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { return }
        AppLogger.shared.info("[DebugSeeder] 导入 \(urls.count) 个调试文件")
        _ = await importService.importFromFiles(urls: urls) { _ in }
        await libraryService.loadSongs()
        await seedPlaylists(libraryService: libraryService, playlistService: playlistService)
    }

    /// 两个自建歌单 + 三首收藏，供歌单页截图
    private static func seedPlaylists(libraryService: MusicLibraryService, playlistService: PlaylistService) async {
        let songs = libraryService.songs
        guard songs.count >= 4 else { return }
        for song in songs.prefix(3) {
            try? await libraryService.toggleFavorite(songId: song.id)
        }
        if let slow = try? await playlistService.createPlaylist(name: "把日子调慢", description: "安静的下午") {
            try? await playlistService.addSongs(songs.prefix(5).map(\.id), to: slow.id)
        }
        if let road = try? await playlistService.createPlaylist(name: "去海边的路上", description: nil) {
            try? await playlistService.addSongs(songs.suffix(3).map(\.id), to: road.id)
        }
        await playlistService.loadPlaylists()
    }
}

/// 仅调试构建：`TUNEHAVEN_DEBUG_ROUTE` 指定启动后落到的页面，供模拟器截图检查。
/// 取值：library、library.artist、library.album、playlist、settings、player、player.lyrics
enum DebugLaunchRoute {
    static var raw: String? { ProcessInfo.processInfo.environment["TUNEHAVEN_DEBUG_ROUTE"] }

    static var libraryTab: LibraryTab? {
        switch raw {
        case "library.artist": return .artist
        case "library.album": return .album
        default: return nil
        }
    }

    @MainActor
    static func apply(router: AppRouter) {
        switch raw {
        case "playlist": router.selectedTab = .playlist
        case "settings": router.selectedTab = .settings
        case "player", "player.lyrics": router.openPlayer()
        default: break
        }
    }
}
#endif

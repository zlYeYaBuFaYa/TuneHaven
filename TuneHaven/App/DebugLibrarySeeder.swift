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
/// 取值：library、library.artist、library.album、playlist、settings、player、player.lyrics、
/// album:<专辑名>|<艺术家>、artist:<艺术家>、search:<关键词>、
/// playlist.detail（第一个自建歌单）、playlist.favorites、playlist.recent、playlist.groups、playlist.batchAdd
enum DebugLaunchRoute {
    static var raw: String? { ProcessInfo.processInfo.environment["TUNEHAVEN_DEBUG_ROUTE"] }

    static var libraryTab: LibraryTab? {
        switch raw {
        case "library.artist": return .artist
        case "library.album": return .album
        default: return nil
        }
    }

    /// `search:<关键词>`：启动后在音乐库搜索框填入关键词
    static var searchQuery: String? {
        guard let raw, raw.hasPrefix("search:") else { return nil }
        return String(raw.dropFirst("search:".count))
    }

    @MainActor
    static func apply(router: AppRouter, playlists: [Playlist] = []) {
        let firstUserPlaylist = playlists.first { !$0.isSystem }
        if let raw, raw.hasPrefix("album:") {
            let parts = raw.dropFirst("album:".count).split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { router.navigate(to: .albumDetail(album: parts[0], artist: parts[1]), in: .library) }
            return
        }
        if let raw, raw.hasPrefix("artist:") {
            router.navigate(to: .artistDetail(name: String(raw.dropFirst("artist:".count))), in: .library)
            return
        }
        switch raw {
        case "playlist": router.selectedTab = .playlist
        case "playlist.detail", "playlist.batchAdd":
            if let id = firstUserPlaylist?.id { router.navigate(to: .playlistDetail(id: id), in: .playlist) }
        case "playlist.favorites":
            router.navigate(to: .songList(title: "我喜欢", context: .favorites), in: .playlist)
        case "playlist.recent":
            router.navigate(to: .songList(title: "最近播放", context: .recentlyPlayed), in: .playlist)
        case "playlist.groups":
            router.selectedTab = .playlist
        case "settings": router.selectedTab = .settings
        case "player", "player.lyrics": router.openPlayer()
        default: break
        }
    }
}
#endif

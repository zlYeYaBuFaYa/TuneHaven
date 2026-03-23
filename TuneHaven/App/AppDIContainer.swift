import SwiftUI

@MainActor
final class AppDIContainer: ObservableObject {
    // MARK: - UI State
    let themeManager: ThemeManager
    let wallpaperManager: WallpaperManager
    let router: AppRouter
    let snackbar: SnackbarState

    // MARK: - Infrastructure
    let audioEngine: AudioEngine

    // MARK: - Services (首屏必须同步创建)
    // 以下 5 个 Service 在首帧即被 View 引用，不能 lazy：
    //  - libraryService: 首屏「音乐库」Tab 显示歌曲列表
    //  - playlistService / groupService: 首屏「歌单」Tab 显示歌单列表与分组
    //  - playbackService: 底部 MiniPlayer + NowPlaying 需立即可用
    //  - searchService: 首屏搜索栏需立即响应
    // 其余 importService / webDAVService / lyricsService 已设为 lazy，仅在用户进入对应页面时创建。
    // TODO: [性能] 若启动耗时明显，可考虑将 Repo 创建移至后台、Service init 改为 async，或对 searchService 做 lazy 延迟到首次搜索时创建
    let libraryService: MusicLibraryService
    let playlistService: PlaylistService
    let groupService: PlaylistGroupService
    let playbackService: PlaybackService
    let searchService: SearchService

    // MARK: - Services (非首屏，延迟创建)
    lazy var importService: ImportService = {
        ImportService(songRepo: songRepo, fileService: FileStorageService.shared)
    }()
    lazy var webDAVService: WebDAVService = {
        WebDAVService(accountStore: WebDAVAccountStore.shared)
    }()
    lazy var lyricsService: LyricsService = {
        LyricsService(repo: songRepo, api: LRCLibAPIClient.shared)
    }()

    // MARK: - Shared Repositories
    private let songRepo: SongRepository
    private let playlistRepo: PlaylistRepository

    init() {
        self.audioEngine = AudioEngine.shared

        self.themeManager = ThemeManager()
        self.wallpaperManager = WallpaperManager()
        self.router = AppRouter()
        self.snackbar = SnackbarState()

        let songRepo: SongRepository = CoreDataSongRepository()
        let playlistRepo: PlaylistRepository = CoreDataPlaylistRepository()
        let groupRepo: PlaylistGroupRepository = CoreDataPlaylistGroupRepository()
        let searchHistoryRepo: SearchHistoryRepository = CoreDataSearchHistoryRepository()

        self.songRepo = songRepo
        self.playlistRepo = playlistRepo

        let libraryService = MusicLibraryService(songRepo: songRepo)
        self.libraryService = libraryService
        self.playlistService = PlaylistService(repo: playlistRepo, songRepo: songRepo)
        self.groupService = PlaylistGroupService(repo: groupRepo)
        self.searchService = SearchService(historyRepo: searchHistoryRepo)
        self.playbackService = PlaybackService(
            playlistRepo: playlistRepo,
            songRepo: songRepo,
            queueService: PlayQueueService(),
            libraryService: libraryService,
            engine: AudioEngine.shared
        )
    }
}

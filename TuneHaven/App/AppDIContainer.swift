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

    // MARK: - Services (首屏)
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
        WebDAVService()
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

        self.libraryService = MusicLibraryService(songRepo: songRepo)
        self.playlistService = PlaylistService(repo: playlistRepo, songRepo: songRepo)
        self.groupService = PlaylistGroupService(repo: groupRepo)
        self.searchService = SearchService(historyRepo: searchHistoryRepo)
        self.playbackService = PlaybackService(playlistRepo: playlistRepo, songRepo: songRepo)

        self.playbackService.configure(libraryService: self.libraryService)
    }
}

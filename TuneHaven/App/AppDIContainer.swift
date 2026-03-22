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

    // MARK: - Services
    let libraryService: MusicLibraryService
    let playlistService: PlaylistService
    let groupService: PlaylistGroupService
    let importService: ImportService
    let searchService: SearchService
    let webDAVService: WebDAVService
    let playbackService: PlaybackService
    let lyricsService: LyricsService

    init() {
        self.audioEngine = AudioEngine.shared

        self.themeManager = ThemeManager()
        self.wallpaperManager = WallpaperManager()
        self.router = AppRouter()
        self.snackbar = SnackbarState()

        self.libraryService = MusicLibraryService()
        self.playlistService = PlaylistService()
        self.groupService = PlaylistGroupService()
        self.importService = ImportService()
        self.searchService = SearchService()
        self.webDAVService = WebDAVService()
        self.lyricsService = LyricsService()
        self.playbackService = PlaybackService()
    }
}

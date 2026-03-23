import SwiftUI

private struct FullEnvironmentModifier: ViewModifier {
    let themeManager: ThemeManager
    let router: AppRouter
    let libraryService: MusicLibraryService
    let playlistService: PlaylistService
    let snackbar: SnackbarState
    let playback: PlaybackService
    let engine: AudioEngine
    let lyricsService: LyricsService

    func body(content: Content) -> some View {
        content
            .environment(\.themePalette, themeManager.palette)
            .environmentObject(themeManager)
            .environmentObject(router)
            .environmentObject(libraryService)
            .environmentObject(playlistService)
            .environmentObject(snackbar)
            .environmentObject(playback)
            .environmentObject(engine)
            .environmentObject(lyricsService)
    }
}

extension View {
    func withFullEnvironment(
        themeManager: ThemeManager,
        router: AppRouter,
        libraryService: MusicLibraryService,
        playlistService: PlaylistService,
        snackbar: SnackbarState,
        playback: PlaybackService,
        engine: AudioEngine,
        lyricsService: LyricsService
    ) -> some View {
        modifier(FullEnvironmentModifier(
            themeManager: themeManager,
            router: router,
            libraryService: libraryService,
            playlistService: playlistService,
            snackbar: snackbar,
            playback: playback,
            engine: engine,
            lyricsService: lyricsService
        ))
    }
}

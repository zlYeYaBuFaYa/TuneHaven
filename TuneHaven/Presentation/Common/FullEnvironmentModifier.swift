import SwiftUI

// TODO: 环境注入集中在一处导致修改面大，后续考虑按功能拆分为多个 ViewModifier
private struct FullEnvironmentModifier: ViewModifier {
    let themeManager: ThemeManager
    let router: AppRouter
    let libraryService: MusicLibraryService
    let playlistService: PlaylistService
    let snackbar: SnackbarState
    let playback: PlaybackService
    let engine: AudioEngine
    let lyricsService: LyricsService
    let subscriptionService: SubscriptionService

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
            .environmentObject(subscriptionService)
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
        lyricsService: LyricsService,
        subscriptionService: SubscriptionService
    ) -> some View {
        modifier(FullEnvironmentModifier(
            themeManager: themeManager,
            router: router,
            libraryService: libraryService,
            playlistService: playlistService,
            snackbar: snackbar,
            playback: playback,
            engine: engine,
            lyricsService: lyricsService,
            subscriptionService: subscriptionService
        ))
    }
}

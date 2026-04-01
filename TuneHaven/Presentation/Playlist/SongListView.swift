import SwiftUI

struct SongListView: View {
    let title: String
    let context: SongListContext

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette
    @AppStorage(AppStorageKey.recentPlayRange) private var recentPlayRange: Int = 7

    @State private var songs: [Song] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if songs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .foregroundColor(palette.iconSecondary)
                    Text("暂无歌曲")
                        .foregroundColor(palette.textSecondary)
                }
            } else {
                List {
                    ForEach(songs) { song in
                        SongRow(
                            song: song,
                            isPlaying: playback.currentSong?.id == song.id,
                            onTap: {
                                Task {
                                    await playContext(song: song)
                                    router.openPlayer()
                                }
                            }
                        )
                        .listRowBackground(palette.surface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .adaptiveBackground()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.surface, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        let days = recentPlayRange
        switch context {
        case .favorites:
            songs = await playlistService.fetchFavorites()
        case .recentlyPlayed:
            songs = await libraryService.fetchRecentlyPlayed(days: days, page: 0).items
        case .allSongs:
            songs = await libraryService.fetchAllSongs(sortBy: .title, ascending: true)
        default:
            songs = []
        }
        isLoading = false
    }

    private func playContext(song: Song) async {
        let ctx: PlayContext
        let days = recentPlayRange
        switch context {
        case .allSongs: ctx = .allSongs(sortBy: .title)
        case .favorites:
            let favId = playlistService.playlists.first { $0.systemType == .favorites }?.id
            ctx = favId.map { .playlist(id: $0) } ?? .allSongs(sortBy: .title)
        case .recentlyPlayed: ctx = .recentlyPlayed(days: days)
        case .artist(let name): ctx = .artist(name: name)
        case .album(let name, let artist): ctx = .album(name: name, artist: artist)
        case .playlist(let id): ctx = .playlist(id: id)
        }
        await playback.play(song: song, in: ctx)
    }
}

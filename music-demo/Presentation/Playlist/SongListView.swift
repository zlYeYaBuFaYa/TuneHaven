import SwiftUI

struct SongListView: View {
    let title: String
    let context: SongListContext

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var playback = PlaybackService.shared
    @Environment(\.themePalette) private var palette

    @State private var songs: [Song] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if songs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
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
                                    await prepareContext(song: song)
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
        switch context {
        case .favorites:
            songs = await playlistService.fetchFavorites()
        case .recentlyPlayed:
            songs = await libraryService.fetchRecentlyPlayed(days: 30, page: 0).items
        case .allSongs:
            songs = await makeSongRepo().fetchAll(sortBy: .title, ascending: true)
        default:
            songs = []
        }
        isLoading = false
    }

    private func prepareContext(song: Song) async {
        let ctx: PlayContext
        switch context {
        case .allSongs: ctx = .allSongs(sortBy: .title)
        case .favorites: ctx = .playlist(id: UUID())
        case .recentlyPlayed: ctx = .allSongs(sortBy: .importDate)
        case .artist(let name): ctx = .artist(name: name)
        case .album(let name, let artist): ctx = .album(name: name, artist: artist)
        case .playlist(let id): ctx = .playlist(id: id)
        }
        await playback.prepare(song: song, in: ctx)
    }
}

private func makeSongRepo() -> CoreDataSongRepository { CoreDataSongRepository() }

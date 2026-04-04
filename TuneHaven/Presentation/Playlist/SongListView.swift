import SwiftUI

struct SongListView: View {
    let title: String
    let context: SongListContext

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @AppStorage(AppStorageKey.recentPlayRange) private var recentPlayRange: Int = 7

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var currentPage = 0
    @State private var hasMorePages = true
    private static let pageSize = 100

    private var isFavorites: Bool { context == .favorites }
    private var isPaginated: Bool { context == .recentlyPlayed }

    var body: some View {
        Group {
            if isLoading && songs.isEmpty {
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
                                    await playSong(song)
                                    router.openPlayer()
                                }
                            },
                            onFavorite: isFavorites ? {
                                Task { await unfavorite(song) }
                            } : nil,
                            onAddToPlaylist: isFavorites ? {
                                router.present(.addToPlaylist(songIds: [song.id]))
                            } : nil,
                            onInsertNext: isFavorites ? {
                                _ = playback.queue.insertNext(song)
                            } : nil
                        )
                        .listRowBackground(palette.surface)
                        .onAppear {
                            if isPaginated && hasMorePages && song.id == songs.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }

                    if isPaginated && hasMorePages {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

                    Color.clear
                        .frame(height: MiniPlayerLayout.listBottomPadding)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
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
        currentPage = 0
        let days = recentPlayRange
        switch context {
        case .favorites:
            songs = await playlistService.fetchFavorites()
        case .recentlyPlayed:
            let result = await libraryService.fetchRecentlyPlayed(days: days, page: 0, pageSize: Self.pageSize)
            songs = result.items
            hasMorePages = result.items.count >= Self.pageSize
        case .allSongs:
            songs = await libraryService.fetchAllSongs(sortBy: .title, ascending: true)
        default:
            songs = []
        }
        isLoading = false
    }

    private func loadMore() async {
        guard isPaginated, hasMorePages, !isLoading else { return }
        isLoading = true
        currentPage += 1
        let days = recentPlayRange
        let result = await libraryService.fetchRecentlyPlayed(days: days, page: currentPage, pageSize: Self.pageSize)
        songs.append(contentsOf: result.items)
        hasMorePages = result.items.count >= Self.pageSize
        isLoading = false
    }

    private func playSong(_ song: Song) async {
        let startIndex = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        playback.queue.replaceQueue(with: songs, startAt: startIndex)
        await playback.play(song: song, in: .queue)
    }

    private func unfavorite(_ song: Song) async {
        let songId = song.id
        do {
            try await libraryService.toggleFavorite(songId: songId)
            songs.removeAll { $0.id == songId }
            snackbar.show(
                message: "已取消收藏「\(song.title)」",
                actionTitle: "撤销",
                action: {
                    Task {
                        do {
                            try await libraryService.toggleFavorite(songId: songId)
                            await load()
                        } catch {
                            snackbar.show(message: "撤销失败")
                        }
                    }
                }
            )
        } catch {
            snackbar.show(message: "操作失败，请重试")
        }
    }
}

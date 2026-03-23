import SwiftUI

struct AllSongsView: View {
    @Binding var sortOption: SongSortOption
    @Binding var isAscending: Bool
    @Binding var formatFilter: AudioFormat

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var playback: PlaybackService
    @State private var pendingDeleteToken: UndoToken?
    @State private var displaySongs: [Song] = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if displaySongs.isEmpty {
                EmptyStateView.noSongs { router.present(.importFromFiles) }
            } else {
                songList
            }
        }
        .onAppear {
            recomputeDisplaySongs()
            Task { await libraryService.loadSongs(sortBy: sortOption, ascending: isAscending) }
        }
        .onChange(of: libraryService.songs) { _, _ in recomputeDisplaySongs() }
        .onChange(of: formatFilter) { _, _ in recomputeDisplaySongs() }
    }

    private func recomputeDisplaySongs() {
        let base = libraryService.songs
        displaySongs = formatFilter == .all ? base : base.filter { $0.metadata.format.lowercased() == formatFilter.rawValue }
    }

    private var toolbar: some View {
        HStack {
            Text("\(displaySongs.count) 首")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
            Spacer()
            Menu {
                ForEach(AudioFormat.allCases, id: \.self) { fmt in
                    Button {
                        formatFilter = fmt
                    } label: {
                        HStack {
                            Text(fmt.displayName)
                            if formatFilter == fmt { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label(formatFilter == .all ? "全部格式" : formatFilter.rawValue.uppercased(),
                      systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Menu {
                ForEach(SongSortOption.allCases, id: \.self) { opt in
                    Button {
                        if sortOption == opt {
                            isAscending.toggle()
                        } else {
                            sortOption = opt
                            isAscending = true
                        }
                        Task { await libraryService.loadSongs(sortBy: sortOption, ascending: isAscending) }
                    } label: {
                        HStack {
                            Text(opt.displayName)
                            if sortOption == opt {
                                Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isAscending ? "arrow.up" : "arrow.down")
                    Text(sortOption.displayName)
                }
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var songList: some View {
        List {
            ForEach(displaySongs) { song in
                SongRow(
                    song: song,
                    isPlaying: playback.currentSong?.id == song.id,
                    onTap: {
                        Task {
                            await playback.prepare(song: song, in: .allSongs(sortBy: sortOption))
                            router.openPlayer()
                        }
                    },
                    onFavorite: { Task { try? await libraryService.toggleFavorite(songId: song.id) } },
                    onDelete: { softDelete(song) },
                    onAddToPlaylist: { router.present(.addToPlaylist(songIds: [song.id])) },
                    onInsertNext: { _ = playback.queue.insertNext(song) }
                )
                .listRowBackground(palette.surface)
                .listRowSeparatorTint(palette.separator)
            }
        }
        .listStyle(.plain)
        .adaptiveBackground()
        .scrollContentBackground(.hidden)
    }

    private func softDelete(_ song: Song) {
        Task {
            do {
                let token = try await libraryService.softDelete(songIds: [song.id])
                pendingDeleteToken = token
                snackbar.show(
                    message: "已删除《\(song.title)》",
                    actionTitle: "撤销",
                    action: { undoDelete(token) },
                    duration: 30
                )
            } catch {
                snackbar.show(message: "删除失败，请重试")
            }
        }
    }

    private func undoDelete(_ token: UndoToken) {
        Task {
            do {
                try await libraryService.undoDelete(token: token)
            } catch {
                snackbar.show(message: "撤销删除失败，请重试")
            }
        }
    }
}

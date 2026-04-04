import SwiftUI

struct ArtistDetailView: View {
    let artistName: String

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var playback: PlaybackService
    @State private var detail: ArtistDetail? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                content(detail: detail)
            } else {
                EmptyStateView(icon: "person.crop.circle", title: "未找到艺术家")
            }
        }
        .adaptiveBackground()
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.surface, for: .navigationBar)
        .task { await load() }
        .onChange(of: libraryService.songs.count) { _ in
            Task { await load() }
        }
    }

    @ViewBuilder
    private func content(detail: ArtistDetail) -> some View {
        List {
            // 艺术家信息头部
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(palette.primary.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Text(String(artistName.prefix(1)))
                            .font(.title.bold())
                            .foregroundColor(palette.primary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artistName)
                            .font(.title2.bold())
                            .foregroundColor(palette.textPrimary)
                        Text("\(detail.albums.count) 张专辑 · \(detail.allSongs.count) 首歌曲")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                    }
                    Spacer()
                    Button {
                        if let first = detail.allSongs.first {
                            Task { await playback.play(song: first, in: .artist(name: artistName)) }
                        }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .foregroundColor(palette.primary)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(palette.surface)
            }

            // 专辑列表
            if !detail.albums.isEmpty {
                Section("专辑") {
                    ForEach(detail.albums) { album in
                        Button {
                            router.navigate(to: .albumDetail(album: album.name, artist: artistName))
                        } label: {
                            AlbumRow(album: album)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }

            // 全部歌曲
            Section("全部歌曲") {
                let currentSongId = playback.currentSong?.id
                ForEach(detail.allSongs) { song in
                    SongRow(
                        song: song,
                        isPlaying: currentSongId == song.id,
                        onTap: {
                            Task {
                                await playback.play(song: song, in: .artist(name: artistName))
                                router.openPlayer()
                            }
                        },
                        onFavorite: {
                            Task {
                                do { try await libraryService.toggleFavorite(songId: song.id) }
                                catch { snackbar.show(message: "收藏操作失败") }
                            }
                        },
                        onDelete: {
                            SongDeletionHelper.softDelete(song: song, libraryService: libraryService, snackbar: snackbar)
                        },
                        onAddToPlaylist: { router.present(.addToPlaylist(songIds: [song.id])) },
                        onInsertNext: { _ = playback.queue.insertNext(song) }
                    )
                    .listRowBackground(palette.surface)
                    .listRowSeparatorTint(palette.separator)
                }
            }

            Section {
                Color.clear.frame(height: MiniPlayerLayout.listBottomPadding)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }

    private func load() async {
        isLoading = true
        detail = await libraryService.fetchArtistDetail(artist: artistName)
        isLoading = false
    }
}

// MARK: - AlbumRow（公共组件）

struct AlbumRow: View {
    let album: AlbumGroup
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(path: album.coverImagePath, size: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let year = album.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                        Text("·")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                    Text("\(album.songCount) 首")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
        }
        .padding(.vertical, 4)
    }
}

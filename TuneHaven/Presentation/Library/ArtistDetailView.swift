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
        .navigationBarTitleDisplayMode(.inline)
        .themeNavigationBarSurface()
        .task { await load() }
        .onChange(of: libraryService.songs.count) { _ in
            Task { await load() }
        }
    }

    /// 艺术家详情（docs/UI设计文档.md §7.5 延伸规则）：头像头部 → 播放按钮 → 专辑横排 → 全部歌曲
    @ViewBuilder
    private func content(detail: ArtistDetail) -> some View {
        List {
            header(detail: detail)
                .plainListRow(insets: EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))

            if !detail.albums.isEmpty {
                ListSectionTitle(title: "专辑", count: detail.albums.count)
                    .plainListRow(insets: EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(detail.albums) { album in
                            Button {
                                router.navigate(to: .albumDetail(album: album.name, artist: artistName))
                            } label: {
                                AlbumGridCell(album: album)
                                    .frame(width: 140)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .plainListRow(insets: EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0))
            }

            ListSectionTitle(title: "全部歌曲", count: detail.allSongs.count)
                .plainListRow(insets: EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))

            let currentSongId = playback.currentSong?.id
            ForEach(detail.allSongs) { song in
                SongRow(
                    song: song,
                    isPlaying: currentSongId == song.id,
                    isPlaybackActive: playback.isPlaying,
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
                    onInsertNext: { SongQueueHelper.insertNext(song: song, playback: playback, snackbar: snackbar) }
                )
                .clearListRow()
                .listRowSeparatorTint(palette.separator)
            }

            Color.clear.frame(height: MiniPlayerLayout.listBottomPadding)
                .accessibilityHidden(true)
                .plainListRow(insets: EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func header(detail: ArtistDetail) -> some View {
        VStack(spacing: 12) {
            ArtistAvatar(name: artistName, size: 112)
                .shadow(color: palette.cardShadow, radius: 16, y: 8)
            VStack(spacing: 4) {
                Text(artistName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(detail.albums.count) 张专辑 · \(detail.allSongs.count) 首歌曲")
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            DetailPlayButtons(
                isEnabled: !detail.allSongs.isEmpty,
                onPlay: {
                    if let first = detail.allSongs.first {
                        Task { await playback.play(song: first, in: .artist(name: artistName)) }
                    }
                },
                onShuffle: {
                    if let random = detail.allSongs.randomElement() {
                        if playback.playMode != .shuffle {
                            playback.setPlayMode(.shuffle)
                        }
                        Task { await playback.play(song: random, in: .artist(name: artistName)) }
                    }
                }
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
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
    /// 替代「年份 · N 首」的副标题（搜索结果显示艺术家）
    var subtitle: String? = nil
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(path: album.coverImagePath, size: 48, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle ?? [album.year.map(String.init), "\(album.songCount) 首"].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
        .frame(minHeight: 56)
    }
}

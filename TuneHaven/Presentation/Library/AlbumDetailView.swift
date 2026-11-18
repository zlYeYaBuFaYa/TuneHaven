import SwiftUI

/// 专辑详情（docs/UI设计文档.md §7.5 延伸规则）：大封面头部 → 播放全部／随机播放 → 曲目列表
struct AlbumDetailView: View {
    let albumName: String
    let artistName: String

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var playback: PlaybackService
    @State private var detail: AlbumDetail? = nil
    @State private var isLoading = true

    private var context: PlayContext { .album(name: albumName, artist: artistName) }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                content(detail: detail)
            } else {
                EmptyStateView(icon: "square.stack", title: "未找到专辑")
            }
        }
        .adaptiveBackground()
        .navigationTitle(albumName)
        .navigationBarTitleDisplayMode(.inline)
        .themeNavigationBarSurface()
        .task { await load() }
        .onChange(of: libraryService.songs.count) { _ in
            Task { await load() }
        }
    }

    @ViewBuilder
    private func content(detail: AlbumDetail) -> some View {
        List {
            header(detail: detail)
                .plainListRow(insets: EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))

            ListSectionTitle(title: "曲目", count: detail.songs.count)
                .plainListRow(insets: EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))

            let currentSongId = playback.currentSong?.id
            ForEach(Array(detail.songs.enumerated()), id: \.element.id) { index, song in
                AlbumTrackRow(
                    index: index + 1,
                    song: song,
                    isCurrent: currentSongId == song.id,
                    isPlaybackActive: playback.isPlaying
                )
                .onTapGesture {
                    Task {
                        await playback.play(song: song, in: context)
                        router.openPlayer()
                    }
                }
                .contextMenu { trackMenu(song) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        SongDeletionHelper.softDelete(song: song, libraryService: libraryService, snackbar: snackbar)
                    } label: { Label("删除", systemImage: "trash") }

                    Button {
                        router.present(.addToPlaylist(songIds: [song.id]))
                    } label: {
                        Label("加入歌单", systemImage: "plus")
                    }
                    .tint(palette.accent)
                }
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

    private func header(detail: AlbumDetail) -> some View {
        VStack(spacing: 14) {
            CoverImageView(path: detail.coverImagePath, size: 200, cornerRadius: 22)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surface.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.separator, lineWidth: 0.5))
                .shadow(color: palette.cardShadow, radius: 18, y: 10)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(albumName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.center)
                Button {
                    router.navigate(to: .artistDetail(name: artistName))
                } label: {
                    Text(artistName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(palette.accent)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开艺术家")
                Text(metaText(detail: detail))
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
            }

            DetailPlayButtons(
                isEnabled: !detail.songs.isEmpty,
                onPlay: {
                    if let first = detail.songs.first {
                        Task { await playback.play(song: first, in: context) }
                    }
                },
                onShuffle: {
                    if let random = detail.songs.randomElement() {
                        if playback.playMode != .shuffle {
                            playback.setPlayMode(.shuffle)
                        }
                        Task { await playback.play(song: random, in: context) }
                    }
                }
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func metaText(detail: AlbumDetail) -> String {
        var parts: [String] = []
        if let year = detail.year { parts.append(String(year)) }
        parts.append("\(detail.songs.count) 首")
        let total = detail.songs.reduce(0) { $0 + $1.duration }
        if total > 0 { parts.append(DurationFormatter.spoken(total)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trackMenu(_ song: Song) -> some View {
        Button { SongQueueHelper.insertNext(song: song, playback: playback, snackbar: snackbar) } label: {
            Label("下一首播放", systemImage: "text.insert")
        }
        Button { router.present(.addToPlaylist(songIds: [song.id])) } label: {
            Label("添加到歌单", systemImage: "text.badge.plus")
        }
        Button(role: .destructive) {
            SongDeletionHelper.softDelete(song: song, libraryService: libraryService, snackbar: snackbar)
        } label: {
            Label("从音乐库删除", systemImage: "trash")
        }
    }

    private func load() async {
        isLoading = true
        detail = await libraryService.fetchAlbumDetail(album: albumName, artist: artistName)
        isLoading = false
    }
}

/// 专辑曲目行：曲序替代封面，当前曲目用强调色与波形
private struct AlbumTrackRow: View {
    let index: Int
    let song: Song
    let isCurrent: Bool
    let isPlaybackActive: Bool

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if isCurrent {
                    WaveformIndicator(color: palette.accent, isAnimating: isPlaybackActive)
                } else {
                    Text(String(format: "%02d", index))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(palette.textSecondary)
                }
            }
            .frame(width: 26)

            Text(song.title)
                .font(.body.weight(isCurrent ? .semibold : .regular))
                .foregroundColor(isCurrent ? palette.accent : palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(song.formatDuration())
                .font(.footnote.monospacedDigit())
                .foregroundColor(palette.textSecondary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(index) 首，\(song.title)，\(song.formatDuration())\(isCurrent ? (isPlaybackActive ? "，正在播放" : "，已暂停") : "")")
        .accessibilityAddTraits(.isButton)
    }
}

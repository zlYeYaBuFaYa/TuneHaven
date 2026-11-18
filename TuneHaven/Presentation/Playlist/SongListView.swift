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

    private var isFavorites: Bool { context == .favorites }

    /// 我喜欢／最近播放（docs/UI设计文档.md §7.5 延伸规则）：图标头部 → 播放按钮 → 歌曲
    var body: some View {
        Group {
            if isLoading && songs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    header
                        .plainListRow(insets: EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))

                    if songs.isEmpty {
                        emptyState
                            .plainListRow()
                    }

                    ForEach(songs) { song in
                        SongRow(
                            song: song,
                            isPlaying: playback.currentSong?.id == song.id,
                            isPlaybackActive: playback.isPlaying,
                            onTap: {
                                Task {
                                    await playSong(song)
                                    router.openPlayer()
                                }
                            },
                            onFavorite: isFavorites ? {
                                Task { await unfavorite(song) }
                            } : nil,
                            onAddToPlaylist: {
                                router.present(.addToPlaylist(songIds: [song.id]))
                            },
                            onInsertNext: {
                                SongQueueHelper.insertNext(song: song, playback: playback, snackbar: snackbar)
                            }
                        )
                        .clearListRow()
                        .listRowSeparatorTint(palette.separator)
                    }

                    Color.clear
                        .frame(height: MiniPlayerLayout.listBottomPadding)
                        .accessibilityHidden(true)
                        .plainListRow(insets: EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .adaptiveBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .themeNavigationBarSurface()
        .task { await load() }
        // 别的页面删除、撤销、收藏或编辑歌曲后，这里同步（交互验收 I-06）
        .onReceive(libraryService.$songs.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { _ in
            Task { await load() }
        }
    }

    private var symbol: String {
        isFavorites ? "heart.fill" : "clock.fill"
    }

    private var subtitle: String {
        var parts = ["\(songs.count) 首"]
        if context == .recentlyPlayed {
            parts.insert(RecentPlayRange(rawValue: recentPlayRange)?.displayName ?? "最近 \(recentPlayRange) 天", at: 0)
        }
        let total = songs.reduce(0) { $0 + $1.duration }
        if total > 0 { parts.append(DurationFormatter.spoken(total)) }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(palette.accent)
                .frame(width: 112, height: 112)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [palette.glowA, palette.glowB],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.separator, lineWidth: 0.5))
                .shadow(color: palette.cardShadow, radius: 16, y: 8)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(palette.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            if !songs.isEmpty {
                DetailPlayButtons(
                    isEnabled: true,
                    onPlay: {
                        guard let first = songs.first else { return }
                        Task { await playSong(first) }
                    },
                    onShuffle: {
                        guard let random = songs.randomElement() else { return }
                        if playback.playMode != .shuffle {
                            playback.setPlayMode(.shuffle)
                        }
                        Task { await playSong(random) }
                    }
                )
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(isFavorites ? "还没有喜欢的歌曲" : "最近没有播放记录")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
            Text(isFavorites ? "在歌曲菜单或播放页点亮心形即可收藏" : "播放过的歌曲会出现在这里")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func load() async {
        isLoading = true
        let days = recentPlayRange
        switch context {
        case .favorites:
            songs = await playlistService.fetchFavorites()
        case .recentlyPlayed:
            songs = await libraryService.fetchRecentlyPlayed(days: days, page: 0, pageSize: 1000).items
        case .allSongs:
            songs = await libraryService.fetchAllSongs(sortBy: .title, ascending: true)
        default:
            songs = []
        }
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

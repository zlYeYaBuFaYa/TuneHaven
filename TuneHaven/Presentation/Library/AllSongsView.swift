import SwiftUI

struct AllSongsView: View {
    @Binding var sortOption: SongSortOption
    @Binding var isAscending: Bool
    @Binding var formatFilter: AudioFormat

    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @EnvironmentObject private var playback: PlaybackService
    @State private var displaySongs: [Song] = []

    var body: some View {
        Group {
            if libraryService.songs.isEmpty {
                EmptyStateView.noSongs { router.present(.importFromFiles) }
            } else {
                songList
            }
        }
        .onAppear {
            recomputeDisplaySongs()
            // 启动时已按保存的排序加载过，排序一致就不再重复加载整个曲库
            if libraryService.currentSort != (sortOption, isAscending) {
                Task { await libraryService.loadSongs(sortBy: sortOption, ascending: isAscending) }
            }
        }
        .onChange(of: libraryService.songs) { _ in recomputeDisplaySongs() }
        .onChange(of: formatFilter) { _ in recomputeDisplaySongs() }
    }

    private func recomputeDisplaySongs() {
        let base = libraryService.songs
        displaySongs = formatFilter == .all ? base : base.filter { $0.metadata.format.lowercased() == formatFilter.rawValue }
    }

    /// 「继续听」只取本机上次有效歌曲；没有或音频缺失时不显示，本次开播后收起交给迷你播放器（交互设计文档 §4.1）
    private var continueSong: Song? {
        guard !playback.hasStartedPlayback,
              let song = playback.currentSong, !song.isAudioMissing else { return nil }
        return song
    }

    private var songList: some View {
        List {
            if let song = continueSong {
                // 直接开播并留在曲库，不展开全屏
                ContinueListeningCard(song: song) {
                    Task { await playback.play(song: song, in: .queue) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
            }

            sectionHeader
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 12))

            if displaySongs.isEmpty {
                Text("没有符合「\(formatFilter.displayName)」的歌曲")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(displaySongs) { song in
                SongRow(
                    song: song,
                    isPlaying: playback.currentSong?.id == song.id,
                    isPlaybackActive: playback.isPlaying,
                    onTap: {
                        Task {
                            await playback.play(song: song, in: .allSongs(sortBy: sortOption))
                            router.openPlayer()
                        }
                    },
                    onFavorite: {
                        Task {
                            do { try await libraryService.toggleFavorite(songId: song.id) }
                            catch { snackbar.show(message: "收藏失败，请重试") }
                        }
                    },
                    onDelete: {
                        SongDeletionHelper.softDelete(song: song, libraryService: libraryService, snackbar: snackbar)
                    },
                    onAddToPlaylist: { router.present(.addToPlaylist(songIds: [song.id])) },
                    onInsertNext: { SongQueueHelper.insertNext(song: song, playback: playback, snackbar: snackbar) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(palette.separator)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8))
            }

            Color.clear
                .frame(height: MiniPlayerLayout.listBottomPadding)
                .accessibilityHidden(true)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .snappy, value: continueSong?.id)
    }

    /// 「所有歌曲 N」与排序／格式筛选菜单（点当前排序项切换升降序）
    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("所有歌曲")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
            Text("\(displaySongs.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(palette.textSecondary)
            Spacer()
            Menu {
                Section("排序") {
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
                            if sortOption == opt {
                                Label(opt.displayName, systemImage: isAscending ? "chevron.up" : "chevron.down")
                            } else {
                                Text(opt.displayName)
                            }
                        }
                    }
                }
                Section("格式") {
                    ForEach(AudioFormat.allCases, id: \.self) { fmt in
                        Button {
                            formatFilter = fmt
                        } label: {
                            if formatFilter == fmt {
                                Label(fmt.displayName, systemImage: "checkmark")
                            } else {
                                Text(fmt.displayName)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(formatFilter == .all ? sortOption.displayName : "\(sortOption.displayName) · \(formatFilter.displayName)")
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("排序与筛选：\(sortOption.displayName)\(isAscending ? "升序" : "降序")，\(formatFilter.displayName)")
        }
    }
}

/// 「继续听」卡（docs/UI设计文档.md §6、§7.1：高约 133–142、圆角 25；内容驱动高度）。
/// 只在本次开播前出现，所以只有「继续播放」一种状态。右侧封面为装饰，不进入可访问树。
struct ContinueListeningCard: View {
    let song: Song
    let onPlay: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("上次播放")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(palette.textSecondary)
                Text(song.title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(2)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
                Button(action: onPlay) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(palette.accent)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(palette.accent.opacity(0.15)))
                        Text("继续播放")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(palette.accent)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("继续播放：\(song.title)")
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            CoverImageView(path: song.coverImagePath, size: 104, cornerRadius: 18)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .accessibilityHidden(true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(palette.surface.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(palette.separator, lineWidth: 0.5)
        )
    }
}

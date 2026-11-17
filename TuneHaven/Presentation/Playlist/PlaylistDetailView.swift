import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: UUID

    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    @State private var detail: PlaylistDetail?
    @State private var showDeleteConfirm = false
    #if DEBUG
    @State private var showBatchAdd = DebugLaunchRoute.raw == "playlist.batchAdd"
    #else
    @State private var showBatchAdd = false
    #endif
    @State private var isDeleted = false
    @State private var searchText = ""
    @State private var sortOption: SongSortOption = .title
    @State private var isAscending: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            playlistSearchBar
            List {
                if let detail {
                    PlaylistContentView(
                        detail: detail,
                        playlistId: playlistId,
                        searchText: searchText,
                        sortOption: sortOption,
                        isAscending: isAscending,
                        onAddSongs: { showBatchAdd = true },
                        sortMenu: { AnyView(sortMenu) }
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .overlay {
            if detail == nil {
                ProgressView()
            }
        }
        .adaptiveBackground()
        .navigationTitle(detail?.playlist.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .themeNavigationBarSurface()
        .toolbar {
            if detail?.playlist.isSystem != true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { router.present(.editPlaylist(id: playlistId)) } label: {
                            Label("编辑歌单", systemImage: "pencil")
                        }
                        Button { showBatchAdd = true } label: {
                            Label("批量添加歌曲", systemImage: "text.badge.plus")
                        }
                        Divider()
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("删除歌单", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundColor(palette.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("歌单操作")
                }
            }
        }
        .confirmationDialog(
            "删除歌单「\(detail?.playlist.name ?? "")」？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除歌单", role: .destructive) {
                Task {
                    do {
                        try await playlistService.deletePlaylist(id: playlistId)
                        isDeleted = true
                        router.popToRoot()
                    } catch {
                        snackbar.show(message: "删除歌单失败，请重试")
                    }
                }
            }
        } message: {
            Text("删除歌单不会删除音乐库中的歌曲")
        }
        .task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
        .onReceive(playlistService.$playlists.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { _ in
            guard !isDeleted else { return }
            Task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
        }
        .sheet(isPresented: $showBatchAdd) {
            BatchAddSongsView(playlistId: playlistId)
                .sheetBackground()
                .environment(\.themePalette, palette)
                .environmentObject(playlistService)
        }
    }

    private var playlistSearchBar: some View {
        SearchBar(text: $searchText, placeholder: "搜索歌单内歌曲")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SongSortOption.allCases, id: \.self) { opt in
                Button {
                    if sortOption == opt {
                        isAscending.toggle()
                    } else {
                        sortOption = opt
                        isAscending = true
                    }
                } label: {
                    if sortOption == opt {
                        Label(opt.displayName, systemImage: isAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(opt.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sortOption.displayName)
                Image(systemName: "line.3.horizontal.decrease")
            }
            .font(.subheadline)
            .foregroundColor(palette.textSecondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("排序：\(sortOption.displayName)\(isAscending ? "升序" : "降序")")
    }
}

private struct PlaylistContentView: View {
    let detail: PlaylistDetail
    let playlistId: UUID
    let searchText: String
    let sortOption: SongSortOption
    let isAscending: Bool
    let onAddSongs: () -> Void
    let sortMenu: () -> AnyView

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 空 query 保持整张歌单。有 query 时只 prepare 一次，三个字段共用拼音规则。
    private func songsForDisplay(allSorted: [Song]) -> [Song] {
        guard isFiltering, let prepared = PinyinSearchMatcher.prepare(searchText) else {
            return allSorted
        }
        let filtered = detail.songs.filter {
            PinyinSearchMatcher.matchesSong($0, query: prepared)
        }
        return applySorting(filtered)
    }

    private func applySorting(_ songs: [Song]) -> [Song] {
        songs.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .title:
                result = a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .fileSize:
                result = a.fileSize < b.fileSize
            case .importDate:
                result = a.importDate < b.importDate
            case .artist:
                result = a.artist.localizedStandardCompare(b.artist) == .orderedAscending
            case .album:
                result = a.album.localizedStandardCompare(b.album) == .orderedAscending
            case .duration:
                result = a.duration < b.duration
            }
            return isAscending ? result : !result
        }
    }

    var body: some View {
        let allSorted = applySorting(detail.songs)
        let displaySongs = songsForDisplay(allSorted: allSorted)

        // 搜索词非空时隐藏封面／简介（交互设计文档 §4.2）
        if !isFiltering {
            PlaylistHeaderSection(
                playlist: detail.playlist,
                songs: detail.songs,
                onPlay: {
                    guard let first = allSorted.first else { return }
                    Task {
                        playback.queue.replaceQueue(with: allSorted, startAt: 0)
                        await playback.play(song: first, in: .queue)
                    }
                },
                onShuffle: {
                    guard let random = allSorted.randomElement(),
                          let index = allSorted.firstIndex(where: { $0.id == random.id }) else { return }
                    if playback.playMode != .shuffle {
                        playback.setPlayMode(.shuffle)
                    }
                    Task {
                        playback.queue.replaceQueue(with: allSorted, startAt: index)
                        await playback.play(song: random, in: .queue)
                    }
                }
            )
            .plainListRow(insets: EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
        }

        if !displaySongs.isEmpty {
            HStack {
                ListSectionTitle(title: isFiltering ? "匹配歌曲" : "歌曲", count: displaySongs.count)
                sortMenu()
            }
            .plainListRow(insets: EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
        }

        if displaySongs.isEmpty {
            if isFiltering {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(palette.accent)
                        .accessibilityHidden(true)
                    Text("没有找到匹配的歌曲")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    Text("试试拼音首字母")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .plainListRow()
            } else {
                VStack(spacing: 12) {
                    Text("这个歌单还没有歌曲")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    if !detail.playlist.isSystem {
                        Button(action: onAddSongs) {
                            Label("添加歌曲", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(palette.onAction)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(palette.actionFill))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .plainListRow()
            }
        } else {
            ForEach(displaySongs) { song in
                SongRow(
                    song: song,
                    isPlaying: playback.currentSong?.id == song.id,
                    isPlaybackActive: playback.isPlaying,
                    onTap: {
                        Task {
                            let startIndex = allSorted.firstIndex(where: { $0.id == song.id }) ?? 0
                            playback.queue.replaceQueue(with: allSorted, startAt: startIndex)
                            await playback.play(song: song, in: .queue)
                            router.openPlayer()
                        }
                    },
                    onFavorite: {
                        Task {
                            do {
                                try await libraryService.toggleFavorite(songId: song.id)
                            } catch {
                                snackbar.show(message: "操作失败，请重试")
                            }
                        }
                    },
                    onDelete: detail.playlist.isSystem ? nil : {
                        Task {
                            do {
                                try await playlistService.removeSongs([song.id], from: playlistId)
                            } catch {
                                snackbar.show(message: "移除歌曲失败，请重试")
                            }
                        }
                    },
                    deleteTitle: "移出歌单",
                    onAddToPlaylist: { router.present(.addToPlaylist(songIds: [song.id])) },
                    onInsertNext: { SongQueueHelper.insertNext(song: song, playback: playback, snackbar: snackbar) }
                )
                .clearListRow()
                .listRowSeparatorTint(palette.separator)
            }
        }

        Color.clear.frame(height: MiniPlayerLayout.listBottomPadding)
            .plainListRow(insets: EdgeInsets())
    }
}

/// 歌单详情头部：前四首封面拼图（无图用占位）、名称、简介、曲数与总时长、播放按钮（交互设计文档 §5.1）
struct PlaylistHeaderSection: View {
    let playlist: Playlist
    let songs: [Song]
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            PlaylistCoverMosaic(songs: songs, fallbackPath: playlist.coverImagePath, size: 180)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(palette.surface.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.separator, lineWidth: 0.5))
                .shadow(color: palette.cardShadow, radius: 18, y: 10)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.title2.weight(.bold))
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.center)
                if let desc = playlist.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Text(metaText)
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            if !songs.isEmpty {
                DetailPlayButtons(isEnabled: true, onPlay: onPlay, onShuffle: onShuffle)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var metaText: String {
        let total = songs.reduce(0) { $0 + $1.duration }
        return total > 0 ? "\(songs.count) 首 · \(DurationFormatter.spoken(total))" : "\(songs.count) 首"
    }
}

/// 前 4 首歌的封面拼成 2×2，缺图或不足 4 首用占位补齐；空歌单用歌单封面或占位（需求文档 §3.6）
struct PlaylistCoverMosaic: View {
    let songs: [Song]
    let fallbackPath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if songs.isEmpty {
                CoverImageView(path: fallbackPath, size: size, cornerRadius: 0)
            } else {
                let paths = songs.prefix(4).map(\.coverImagePath) + Array(repeating: nil, count: max(0, 4 - songs.count))
                let cell = size / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        CoverImageView(path: paths[0], size: cell, cornerRadius: 0)
                        CoverImageView(path: paths[1], size: cell, cornerRadius: 0)
                    }
                    HStack(spacing: 0) {
                        CoverImageView(path: paths[2], size: cell, cornerRadius: 0)
                        CoverImageView(path: paths[3], size: cell, cornerRadius: 0)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

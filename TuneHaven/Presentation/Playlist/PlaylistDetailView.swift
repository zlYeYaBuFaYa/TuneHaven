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
    @State private var showBatchAdd = false
    @State private var isDeleted = false
    @State private var searchText = ""
    @State private var sortOption: SongSortOption = .title
    @State private var isAscending: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            playlistSearchBar
            Divider()
                .background(palette.separator)
            List {
                if let detail {
                    PlaylistContentView(
                        detail: detail,
                        playlistId: playlistId,
                        searchText: searchText,
                        sortOption: sortOption,
                        isAscending: isAscending
                    )
                }
            }
            .listStyle(.insetGrouped)
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
        .toolbarBackground(palette.surface, for: .navigationBar)
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
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(palette.primary)
                    }
                }
            }
        }
        .confirmationDialog("删除歌单", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
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
            if let detail {
                Text("确定要删除「\(detail.playlist.name)」吗？此操作不可撤销。")
            }
        }
        .task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
        .onReceive(playlistService.$playlists.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { _ in
            guard !isDeleted else { return }
            Task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
        }
        .sheet(isPresented: $showBatchAdd) {
            BatchAddSongsView(playlistId: playlistId)
                .environment(\.themePalette, palette)
                .environmentObject(playlistService)
        }
    }

    private var playlistSearchBar: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "搜索歌单内歌曲")
            if detail != nil {
                sortToolbar
            }
        }
    }

    private var sortToolbar: some View {
        HStack {
            Text("\(detail?.songs.count ?? 0) 首")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
            Spacer()
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
        .padding(.vertical, 6)
    }
}

private struct PlaylistContentView: View {
    let detail: PlaylistDetail
    let playlistId: UUID
    let searchText: String
    let sortOption: SongSortOption
    let isAscending: Bool

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        let displaySongs: [Song] = {
            if isFiltering {
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return applySorting(detail.songs.filter {
                    $0.title.lowercased().contains(q) ||
                    $0.artist.lowercased().contains(q) ||
                    $0.album.lowercased().contains(q)
                })
            }
            return allSorted
        }()

        if !isFiltering {
            Section {
                PlaylistHeaderSection(playlist: detail.playlist, songs: detail.songs) {
                    if let first = allSorted.first {
                        Task {
                            playback.queue.replaceQueue(with: allSorted, startAt: 0)
                            await playback.play(song: first, in: .queue)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            if displaySongs.isEmpty {
                if isFiltering {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(palette.iconSecondary)
                        Text("未找到匹配的歌曲")
                            .foregroundColor(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    Text("暂无歌曲，长按歌曲可添加到此歌单")
                        .font(.subheadline)
                        .foregroundColor(palette.textTertiary)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(displaySongs) { song in
                    SongRow(
                        song: song,
                        isPlaying: playback.currentSong?.id == song.id,
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
                        }
                    )
                    .listRowBackground(palette.surface)
                }
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
}

struct PlaylistHeaderSection: View {
    let playlist: Playlist
    let songs: [Song]
    let onPlay: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            CoverImageView(path: playlist.coverImagePath, size: 140, cornerRadius: 12)
                .padding(.top, 20)
            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.title3.bold())
                    .foregroundColor(palette.textPrimary)
                if let desc = playlist.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Text("\(songs.count) 首歌曲")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.horizontal, 32)
            if !songs.isEmpty {
                Button(action: onPlay) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("播放全部")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(palette.primary)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
        .background(palette.surface)
    }
}

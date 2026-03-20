import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: UUID

    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette

    @State private var detail: PlaylistDetail?
    @State private var showDeleteConfirm = false
    @State private var showBatchAdd = false
    @State private var isDeleted = false
    @State private var searchText = ""

    var body: some View {
        List {
            if let detail {
                PlaylistContentView(
                    detail: detail,
                    playlistId: playlistId,
                    searchText: searchText
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "搜索歌单内歌曲")
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
                    HStack(spacing: 16) {
                        Button { showBatchAdd = true } label: {
                            Image(systemName: "plus")
                                .foregroundColor(palette.primary)
                        }
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
        }
        .confirmationDialog("删除歌单", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    isDeleted = true
                    try? await playlistService.deletePlaylist(id: playlistId)
                    router.popToRoot()
                }
            }
        } message: {
            if let detail {
                Text("确定要删除「\(detail.playlist.name)」吗？此操作不可撤销。")
            }
        }
        .task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
        .onReceive(playlistService.$playlists) { _ in
            guard !isDeleted else { return }
            Task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
        }
        .sheet(isPresented: $showBatchAdd) {
            BatchAddSongsView(playlistId: playlistId)
                .environment(\.themePalette, palette)
                .environmentObject(playlistService)
        }
    }
}

private struct PlaylistContentView: View {
    let detail: PlaylistDetail
    let playlistId: UUID
    let searchText: String

    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.isSearching) private var isSearching

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return detail.songs }
        let q = searchText.lowercased()
        return detail.songs.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.album.lowercased().contains(q)
        }
    }

    var body: some View {
        if !isSearching {
            Section {
                PlaylistHeaderSection(playlist: detail.playlist, songs: detail.songs) {
                    if let first = detail.songs.first {
                        Task { await playback.play(song: first, in: .playlist(id: playlistId)) }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            let songs = isSearching ? filteredSongs : detail.songs
            if songs.isEmpty {
                if isSearching && !searchText.isEmpty {
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
                ForEach(songs) { song in
                    SongRow(
                        song: song,
                        isPlaying: playback.currentSong?.id == song.id,
                        onTap: {
                            Task {
                                await playback.prepare(song: song, in: .playlist(id: playlistId))
                                router.openPlayer()
                            }
                        },
                        onFavorite: {
                            Task { try? await libraryService.toggleFavorite(songId: song.id) }
                        },
                        onDelete: detail.playlist.isSystem ? nil : {
                            Task { try? await playlistService.removeSongs([song.id], from: playlistId) }
                        }
                    )
                    .listRowBackground(palette.surface)
                }
            }
        }
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
                    .foregroundColor(.white)
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

import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: UUID

    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var playback = PlaybackService.shared
    @Environment(\.themePalette) private var palette

    @State private var detail: PlaylistDetail?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if let detail {
                List {
                    Section {
                        PlaylistHeaderSection(playlist: detail.playlist, songs: detail.songs) {
                            if let first = detail.songs.first {
                                Task { await playback.play(song: first, in: .playlist(id: playlistId)) }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Section {
                        if detail.songs.isEmpty {
                            Text("暂无歌曲，长按歌曲可添加到此歌单")
                                .font(.subheadline)
                                .foregroundColor(palette.textTertiary)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(detail.songs) { song in
                                SongRow(
                                    song: song,
                                    isPlaying: playback.currentSong?.id == song.id,
                                    onTap: { Task { await playback.play(song: song, in: .playlist(id: playlistId)) } },
                                    onFavorite: {
                                        Task {
                                            let lib = MusicLibraryService()
                                            try? await lib.toggleFavorite(songId: song.id)
                                        }
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
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(palette.background)
                .navigationTitle(detail.playlist.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !detail.playlist.isSystem {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button { router.present(.editPlaylist(id: playlistId)) } label: {
                                    Label("编辑歌单", systemImage: "pencil")
                                }
                                Button { router.present(.playlistCoverPicker(id: playlistId)) } label: {
                                    Label("更换封面", systemImage: "photo")
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
                            try? await playlistService.deletePlaylist(id: playlistId)
                            router.popToRoot(in: .playlist)
                        }
                    }
                } message: {
                    Text("确定要删除「\(detail.playlist.name)」吗？此操作不可撤销。")
                }
            } else {
                ProgressView()
            }
        }
        .task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
        .onReceive(playlistService.$playlists) { _ in
            Task { detail = await playlistService.fetchDetail(playlistId: playlistId) }
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

import SwiftUI

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
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.surface, for: .navigationBar)
        .task { await load() }
    }

    @ViewBuilder
    private func content(detail: AlbumDetail) -> some View {
        List {
            // 专辑封面头部
            Section {
                VStack(spacing: 16) {
                    CoverImageView(path: detail.coverImagePath, size: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .padding(.top, 8)

                    VStack(spacing: 4) {
                        Text(albumName)
                            .font(.title3.bold())
                            .foregroundColor(palette.textPrimary)
                            .multilineTextAlignment(.center)
                        Button {
                            router.navigate(to: .artistDetail(name: artistName))
                        } label: {
                            Text(artistName)
                                .font(.subheadline)
                                .foregroundColor(palette.primary)
                        }
                        HStack(spacing: 8) {
                            if let year = detail.year {
                                Text(String(year)).font(.caption).foregroundColor(palette.textTertiary)
                                Text("·").font(.caption).foregroundColor(palette.textTertiary)
                            }
                            Text("\(detail.songs.count) 首").font(.caption).foregroundColor(palette.textTertiary)
                        }
                    }

                    // 播放全部按钮
                    HStack(spacing: 20) {
                        playButton(icon: "play.fill", title: "播放全部") {
                            if let first = detail.songs.first {
                                Task { await playback.play(song: first, in: .album(name: albumName, artist: artistName)) }
                            }
                        }
                        playButton(icon: "shuffle", title: "随机播放") {
                            if let random = detail.songs.randomElement() {
                                if playback.playMode != .shuffle {
                                    playback.setPlayMode(.shuffle)
                                }
                                Task { await playback.play(song: random, in: .album(name: albumName, artist: artistName)) }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(palette.surface)
            }

            // 曲目列表
            Section {
                ForEach(Array(detail.songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(
                                playback.currentSong?.id == song.id
                                    ? palette.primary
                                    : palette.textTertiary
                            )
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline.weight(playback.currentSong?.id == song.id ? .semibold : .regular))
                                .foregroundColor(playback.currentSong?.id == song.id ? palette.primary : palette.textPrimary)
                                .lineLimit(1)
                            Text(song.formatDuration())
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }
                        Spacer()
                        if playback.currentSong?.id == song.id && playback.isPlaying {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundColor(palette.primary)
                                .symbolEffect(.variableColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await playback.prepare(song: song, in: .album(name: albumName, artist: artistName))
                            router.openPlayer()
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                guard let token = try? await libraryService.softDelete(songIds: [song.id]) else { return }
                                snackbar.show(message: "已删除《\(song.title)》", actionTitle: "撤销") {
                                    Task { try? await libraryService.undoDelete(token: token) }
                                }
                            }
                        } label: { Label("删除", systemImage: "trash") }

                        Button {
                            router.present(.addToPlaylist(songIds: [song.id]))
                        } label: {
                            Label("加入歌单", systemImage: "plus")
                        }
                        .tint(palette.primary)
                    }
                    .listRowBackground(palette.surface)
                    .listRowSeparatorTint(palette.separator)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }

    private func playButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(palette.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(palette.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func load() async {
        isLoading = true
        detail = await libraryService.fetchAlbumDetail(album: albumName, artist: artistName)
        isLoading = false
    }
}

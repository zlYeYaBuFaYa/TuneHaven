import SwiftUI

struct PlayQueueView: View {
    let onClose: () -> Void
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette

    @State private var showSaveAsPlaylist = false
    @State private var savePlaylistName = ""

    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("播放队列")
                    .font(.title3.weight(.bold))
                    .foregroundColor(palette.textPrimary)
                Text("\(playback.queue.count) 首")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭播放队列")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if playback.isPlayingOutsideQueue, let current = playback.currentSong {
                outOfQueueBanner(current)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if playback.queue.queue.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(palette.accent)
                        .accessibilityHidden(true)
                    Text("队列为空")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(playback.queue.queue.enumerated()), id: \.element.id) { idx, item in
                        let isCurrent = idx == playback.queue.currentIndex
                        HStack(spacing: 12) {
                            CoverImageView(path: item.song.coverImagePath, size: 42, cornerRadius: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.song.title)
                                    .font(.body.weight(isCurrent ? .semibold : .regular))
                                    .foregroundColor(isCurrent ? palette.accent : palette.textPrimary)
                                    .lineLimit(1)
                                Text(item.song.artist)
                                    .font(.footnote)
                                    .foregroundColor(palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isCurrent {
                                WaveformIndicator(color: palette.accent, isAnimating: playback.isPlaying)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playback.queue.setCurrentIndex(to: idx)
                            Task { await playback.play(song: item.song, in: .queue) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.song.title)，\(item.song.artist)\(isCurrent ? "，当前播放" : "")")
                        .accessibilityAddTraits(.isButton)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(palette.separator)
                    }
                    .onDelete { offsets in playback.removeFromQueue(at: offsets) }
                    .onMove { src, dst in playback.queue.moveInQueue(from: src, to: dst) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
                HStack(spacing: 20) {
                    Button {
                        showSaveAsPlaylist = true
                    } label: {
                        Label("存为歌单", systemImage: "plus.square.on.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(palette.accent)
                            .frame(minHeight: 44)
                    }
                    Spacer()
                    Button {
                        showClearConfirm = true
                    } label: {
                        Label("清空队列", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundColor(SemanticColor.danger)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog("清空播放队列？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空队列", role: .destructive) { playback.clearQueue() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清空队列，当前歌曲会播完后停止")
        }
        .alert("保存为歌单", isPresented: $showSaveAsPlaylist) {
            TextField("歌单名称", text: $savePlaylistName)
            Button("保存") {
                let name = savePlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    do {
                        try await playback.queue.saveQueueAsPlaylist(
                            name: name,
                            createPlaylist: { n in try await playlistService.createPlaylist(name: n, description: nil) },
                            addSongs: { ids, pid in try await playlistService.addSongs(ids, to: pid) }
                        )
                        snackbar.show(message: "已保存为歌单「\(name)」")
                    } catch {
                        snackbar.show(message: "保存歌单失败")
                    }
                    savePlaylistName = ""
                }
            }
            Button("取消", role: .cancel) { savePlaylistName = "" }
        } message: {
            Text("将当前队列中的 \(playback.queue.queue.count) 首歌曲保存为新歌单")
        }
    }

    /// 队列外播放标记（交互设计文档 §7.5）：当前歌曲已移出队列，播完后从原后继项继续或停止
    private func outOfQueueBanner(_ song: Song) -> some View {
        HStack(spacing: 12) {
            CoverImageView(path: song.coverImagePath, size: 42, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("队列外播放 · \(song.title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text(playback.outOfQueueSuccessor.map { "播完后继续：\($0.title)" } ?? "播完后停止")
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            WaveformIndicator(color: palette.accent, isAnimating: playback.isPlaying)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.accent.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("队列外播放：\(song.title)。" + (playback.outOfQueueSuccessor.map { "播完后继续播放 \($0.title)" } ?? "播完后停止"))
    }
}

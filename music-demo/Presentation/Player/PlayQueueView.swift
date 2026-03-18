import SwiftUI

struct PlayQueueView: View {
    let onClose: () -> Void
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette

    @State private var showSaveAsPlaylist = false
    @State private var savePlaylistName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("播放队列 (\(playback.queue.count) 首)")
                    .font(.headline)
                    .foregroundColor(palette.playerText)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(palette.playerSubtext)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if playback.queue.queue.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(palette.playerSubtext.opacity(0.5))
                    Text("队列为空")
                        .foregroundColor(palette.playerSubtext)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(playback.queue.queue.enumerated()), id: \.element.id) { idx, item in
                        let isCurrent = playback.queue.queue.firstIndex(where: { $0.id == item.id }) == playback.queue.currentIndex
                        HStack(spacing: 12) {
                            CoverImageView(path: item.song.coverImagePath, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.song.title)
                                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                                    .foregroundColor(isCurrent ? palette.primary : palette.playerText)
                                    .lineLimit(1)
                                Text(item.song.artist)
                                    .font(.caption)
                                    .foregroundColor(palette.playerSubtext)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isCurrent {
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundColor(palette.primary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playback.queue.setCurrentIndex(to: idx)
                            Task { await playback.play(song: item.song, in: .queue) }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(palette.progressBackground)
                    }
                    .onDelete { offsets in playback.queue.removeFromQueue(at: offsets) }
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
                            .font(.subheadline)
                            .foregroundColor(palette.primary)
                    }
                    Spacer()
                    Button {
                        playback.queue.clearQueue()
                    } label: {
                        Label("清空队列", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundColor(SemanticColor.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .background(palette.playerBackground)
        .alert("保存为歌单", isPresented: $showSaveAsPlaylist) {
            TextField("歌单名称", text: $savePlaylistName)
            Button("保存") {
                let name = savePlaylistName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    try? await playback.queue.saveQueueAsPlaylist(name: name, playlistService: playlistService)
                    savePlaylistName = ""
                }
            }
            Button("取消", role: .cancel) { savePlaylistName = "" }
        } message: {
            Text("将当前队列中的 \(playback.queue.queue.count) 首歌曲保存为新歌单")
        }
    }
}

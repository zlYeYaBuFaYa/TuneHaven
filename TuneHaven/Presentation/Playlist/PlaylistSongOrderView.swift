import SwiftUI

struct PlaylistSongOrderView: View {
    let playlistId: UUID
    let onSaved: () -> Void
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var originalIDs: [UUID] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("拖动歌曲，或点右侧菜单上移／下移。保存后用于歌单顺序，不会改变正在播放的队列。")
                        .font(.subheadline).foregroundColor(palette.textSecondary).plainListRow()
                }
                if let error {
                    Text(error).foregroundColor(SemanticColor.danger).plainListRow()
                        .accessibilityIdentifier("playlist.order.error")
                }
                ForEach(songs) { song in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).foregroundColor(palette.textPrimary)
                            Text(song.artist).font(.footnote).foregroundColor(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        OrderMoveMenu(title: song.title, canMoveUp: songs.first?.id != song.id,
                                      canMoveDown: songs.last?.id != song.id) { offset in
                            guard let index = songs.firstIndex(where: { $0.id == song.id }),
                                  songs.indices.contains(index + offset) else { return }
                            songs.swapAt(index, index + offset)
                        }
                        .disabled(isSaving)
                    }
                    .flowRowSurface()
                    .moveDisabled(isSaving)
                    .accessibilityIdentifier("playlist.order.song.\(song.id)")
                }
                .onMove { source, target in songs.move(fromOffsets: source, toOffset: target) }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .overlay { if isLoading { ProgressView("正在读取歌单") } }
            .navigationTitle("调整歌曲顺序")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "正在保存…" : "保存", action: save)
                        .disabled(isLoading || isSaving || songs.map(\.id) == originalIDs)
                        .accessibilityIdentifier("playlist.order.save")
                }
            }
            .sheetBackground()
            .interactiveDismissDisabled(isSaving)
            .task {
                if let detail = await playlistService.fetchDetail(playlistId: playlistId) {
                    songs = detail.songs
                    originalIDs = songs.map(\.id)
                } else { error = "无法读取歌单，请关闭后重试" }
                isLoading = false
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do {
                try await playlistService.reorderSongs(in: playlistId, orderedSongIds: songs.map(\.id))
                onSaved()
                dismiss()
            } catch {
                self.error = "保存失败。若歌单内容已变化，请关闭后重新排序。"
                isSaving = false
            }
        }
    }
}

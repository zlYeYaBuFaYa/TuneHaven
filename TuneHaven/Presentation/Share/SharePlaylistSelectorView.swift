import SwiftUI

struct SharePlaylistSelectorView: View {
    let onSelected: ([PlaylistDetail]) -> Void

    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette

    @State private var playlists: [Playlist] = []
    @State private var selectedIds: Set<UUID> = []
    @State private var isSharing = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private var orderedSelectedPlaylists: [Playlist] {
        playlists.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if playlists.isEmpty {
                    Text("暂无歌单")
                        .font(.subheadline)
                        .foregroundColor(palette.textTertiary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(playlists) { playlist in
                        Button {
                            if selectedIds.contains(playlist.id) {
                                selectedIds.remove(playlist.id)
                            } else {
                                selectedIds.insert(playlist.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIds.contains(playlist.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedIds.contains(playlist.id) ? palette.primary : palette.textSecondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(palette.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text("\(playlist.songCount) 首")
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.surface)
                        .listRowSeparatorTint(palette.separator)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            bottomBar
        }
        .adaptiveBackground()
        .navigationTitle("选择歌单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("全选") {
                    selectedIds = Set(playlists.map(\.id))
                }
                .disabled(playlists.isEmpty)

                Button("取消全选") {
                    selectedIds.removeAll()
                }
                .disabled(selectedIds.isEmpty)
            }
        }
        .alert("提示", isPresented: $showErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await playlistService.loadPlaylists()
            playlists = playlistService.playlists.filter { !$0.isSystem }.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(palette.separator)
            HStack {
                Text("已选 \(selectedIds.count) 个歌单")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Button("开始分享") {
                    Task { await shareSelected() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selectedIds.isEmpty || isSharing ? palette.textSecondary : palette.primary)
                .disabled(selectedIds.isEmpty || isSharing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(palette.surface)
        }
    }

    private func shareSelected() async {
        guard !selectedIds.isEmpty else {
            errorMessage = "请至少选择一个歌单"
            showErrorAlert = true
            return
        }
        isSharing = true
        var details: [PlaylistDetail] = []
        for playlist in orderedSelectedPlaylists {
            if let detail = await playlistService.fetchDetail(playlistId: playlist.id) {
                details.append(detail)
            }
        }
        isSharing = false
        guard details.count == orderedSelectedPlaylists.count else {
            errorMessage = "部分歌单加载失败，请重试"
            showErrorAlert = true
            return
        }
        onSelected(details)
    }
}

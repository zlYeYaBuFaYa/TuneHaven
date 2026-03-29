import SwiftUI

struct ExportPlaylistSelectorView: View {
    @EnvironmentObject private var syncExportService: SyncExportService
    @EnvironmentObject private var playlistService: PlaylistService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [Playlist] = []
    @State private var selectedIds: Set<UUID> = []
    @State private var includeAudio = true
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var estimatedSize = ""
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private var userPlaylists: [Playlist] {
        playlists.filter { !$0.isSystem }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                selectionHeader
                List {
                    audioToggleSection
                    playlistListSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .adaptiveBackground()
            .navigationTitle("选择歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导出") { Task { await exportSelected() } }
                        .foregroundColor(palette.primary)
                        .disabled(selectedIds.isEmpty || syncExportService.isExporting)
                }
            }
        }
        .task {
            await playlistService.loadPlaylists()
            playlists = playlistService.playlists
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .alert("导出失败", isPresented: $showErrorAlert) {
            Button("确定") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var selectionHeader: some View {
        HStack {
            Button(selectedIds.count == userPlaylists.count ? "取消全选" : "全选") {
                if selectedIds.count == userPlaylists.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(userPlaylists.map(\.id))
                }
                updateEstimatedSize()
            }
            .font(.subheadline)
            .foregroundColor(palette.primary)

            Spacer()

            Text("已选 \(selectedIds.count) 个")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)

            if !estimatedSize.isEmpty {
                Text("· \(estimatedSize)")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var audioToggleSection: some View {
        Section {
            Toggle(isOn: $includeAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("包含音频文件")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text("关闭则仅导出歌单结构（歌曲引用）")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            }
            .tint(palette.primary)
            .onChange(of: includeAudio) { _ in updateEstimatedSize() }
        }
    }

    private var playlistListSection: some View {
        Section {
            ForEach(userPlaylists) { playlist in
                Button {
                    toggleSelection(playlist.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIds.contains(playlist.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedIds.contains(playlist.id) ? palette.primary : palette.textSecondary)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)
                            Text("\(playlist.songCount) 首歌曲")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }

                        Spacer()
                    }
                }
            }
        } header: {
            Text("自建歌单")
                .foregroundColor(palette.textSecondary)
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        updateEstimatedSize()
    }

    private func updateEstimatedSize() {
        Task {
            var details: [PlaylistDetail] = []
            for id in selectedIds {
                if let detail = await playlistService.fetchDetail(playlistId: id) {
                    details.append(detail)
                }
            }
            estimatedSize = syncExportService.estimateSize(
                songs: [], playlists: details, includeAudioFiles: includeAudio
            )
        }
    }

    private func exportSelected() async {
        var details: [PlaylistDetail] = []
        for id in selectedIds {
            if let detail = await playlistService.fetchDetail(playlistId: id) {
                details.append(detail)
            }
        }
        guard !details.isEmpty else { return }

        do {
            let url = try await syncExportService.exportPlaylists(details, includeAudioFiles: includeAudio)
            shareURL = url
            showShare = true
        } catch {
            AppLogger.shared.error(error, context: "ExportPlaylistSelector 导出失败")
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}

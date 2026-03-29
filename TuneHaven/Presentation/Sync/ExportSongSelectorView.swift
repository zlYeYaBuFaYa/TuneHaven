import SwiftUI

struct ExportSongSelectorView: View {
    @EnvironmentObject private var syncExportService: SyncExportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var songs: [Song] = []
    @State private var selectedIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var estimatedSize = ""
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return songs }
        let query = searchText.lowercased()
        return songs.filter {
            $0.title.lowercased().contains(query) ||
            $0.artist.lowercased().contains(query) ||
            $0.album.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                selectionHeader
                List(filteredSongs) { song in
                    songRow(song)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "搜索歌曲")
            }
            .adaptiveBackground()
            .navigationTitle("选择歌曲")
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
            songs = await libraryService.fetchAllSongs()
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
            Button(selectedIds.count == songs.count ? "取消全选" : "全选") {
                if selectedIds.count == songs.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(songs.map(\.id))
                }
            }
            .font(.subheadline)
            .foregroundColor(palette.primary)

            Spacer()

            Text("已选 \(selectedIds.count) 首")
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

    private func songRow(_ song: Song) -> some View {
        Button {
            toggleSelection(song.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedIds.contains(song.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedIds.contains(song.id) ? palette.primary : palette.textSecondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(song.artist) · \(song.album)")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(SyncExportService.formatFileSize(song.fileSize))
                    .font(.caption2)
                    .foregroundColor(palette.textSecondary)
            }
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
        let selected = songs.filter { selectedIds.contains($0.id) }
        estimatedSize = syncExportService.estimateSize(
            songs: selected, playlists: [], includeAudioFiles: true
        )
    }

    private func exportSelected() async {
        let selected = songs.filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        do {
            let url = try await syncExportService.exportSongs(selected)
            shareURL = url
            showShare = true
        } catch {
            AppLogger.shared.error(error, context: "ExportSongSelector 导出失败")
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

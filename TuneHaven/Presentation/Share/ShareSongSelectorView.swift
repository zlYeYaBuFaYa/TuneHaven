import SwiftUI

struct ShareSongSelectorView: View {
    let onSelected: ([Song]) -> Void

    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette

    @State private var selectedIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var filteredSongs: [Song] = []
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = .useAll
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(filteredSongs) { song in
                    Button {
                        if selectedIds.contains(song.id) {
                            selectedIds.remove(song.id)
                        } else {
                            selectedIds.insert(song.id)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedIds.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedIds.contains(song.id) ? palette.primary : palette.textSecondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                                Text(Self.byteFormatter.string(fromByteCount: song.fileSize))
                                    .font(.caption2)
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            bottomBar
        }
        .adaptiveBackground()
        .navigationTitle("选择歌曲")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索标题或艺术家")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("全选") {
                    selectedIds = Set(filteredSongs.map(\.id))
                }
                .disabled(filteredSongs.isEmpty)

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
            await libraryService.loadSongs()
            await updateFilteredSongsAsync()
        }
        .onChange(of: searchText) { _ in
            Task { await updateFilteredSongsAsync() }
        }
        .onChange(of: libraryService.songs) { _ in
            Task { await updateFilteredSongsAsync() }
        }
    }

    private func updateFilteredSongsAsync() async {
        let base = libraryService.songs
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result: [Song] = await Task.detached(priority: .userInitiated) {
            guard !q.isEmpty else { return base }
            return base.filter {
                $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
            }
        }.value
        await MainActor.run { filteredSongs = result }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(palette.separator)
            HStack {
                Text("已选 \(selectedIds.count) 首")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Button("开始分享") {
                    guard !selectedIds.isEmpty else {
                        errorMessage = "请至少选择一首歌曲"
                        showErrorAlert = true
                        return
                    }
                    let songs = libraryService.songs.filter { selectedIds.contains($0.id) }
                    onSelected(songs)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selectedIds.isEmpty ? palette.textSecondary : palette.primary)
                .disabled(selectedIds.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(palette.surface)
        }
    }
}

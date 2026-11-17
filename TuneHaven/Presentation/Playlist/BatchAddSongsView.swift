import SwiftUI

struct BatchAddSongsView: View {
    let playlistId: UUID

    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var allSongs: [Song] = []
    @State private var existingSongIds: Set<UUID> = []
    @State private var selectedIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @StateObject private var searchDebouncer = SearchDebouncer()
    @State private var filteredSongs: [Song] = []
    @State private var groupedByArtist: [(String, [Song])] = []
    @State private var recomputeFilteredToken = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                fixedHeader

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if allSongs.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(palette.accent)
                            .accessibilityHidden(true)
                        Text("音乐库中暂无歌曲")
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                    }
                    Spacer()
                } else {
                    songList
                }
            }
            .adaptiveBackground()
            .navigationTitle("添加歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await addSelected() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(selectedIds.isEmpty ? "添加" : "添加 \(selectedIds.count) 首")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(palette.accent)
                    .disabled(selectedIds.isEmpty || isSaving)
                }
            }
        }
        .task { await loadData() }
        .onChange(of: searchText) { newValue in
            searchDebouncer.send(newValue)
            if newValue.isEmpty { recomputeFiltered(query: "") }
        }
        .onChange(of: searchDebouncer.debouncedQuery) { query in
            recomputeFiltered(query: query)
        }
        .onChange(of: allSongs) { _ in recomputeFiltered(query: searchDebouncer.debouncedQuery) }
    }

    private func recomputeFiltered(query: String) {
        recomputeFilteredToken += 1
        let token = recomputeFilteredToken
        let songs = allSongs
        Task.detached {
            let available = songs
            let filtered: [Song]
            if query.isEmpty {
                filtered = available
            } else {
                let keyword = query.lowercased()
                filtered = available.filter {
                    $0.title.lowercased().contains(keyword) ||
                    $0.artist.lowercased().contains(keyword) ||
                    $0.album.lowercased().contains(keyword)
                }
            }
            let grouped = Dictionary(grouping: filtered) { $0.artist }
            let sorted = grouped.sorted { $0.key < $1.key }
            await MainActor.run {
                guard token == recomputeFilteredToken else { return }
                filteredSongs = filtered
                groupedByArtist = sorted
            }
        }
    }

    private var fixedHeader: some View {
        SearchBar(text: $searchText, placeholder: "搜索歌曲、艺术家、专辑")
    }

    /// 可选择的歌曲（已在歌单中的不计入全选与数量）
    private func selectableIds(_ songs: [Song]) -> Set<UUID> {
        Set(songs.lazy.map(\.id).filter { !existingSongIds.contains($0) })
    }

    private var songList: some View {
        List {
            if !filteredSongs.isEmpty {
                selectAllRow
                    .plainListRow(insets: EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 12))
            } else if !searchText.isEmpty {
                Text("没有找到匹配的歌曲")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .plainListRow()
            }

            ForEach(groupedByArtist, id: \.0) { artist, songs in
                let sectionIds = selectableIds(songs)
                let sectionAllSelected = !sectionIds.isEmpty && sectionIds.isSubset(of: selectedIds)
                HStack {
                    ListSectionTitle(title: artist, count: songs.count)
                    if !sectionIds.isEmpty {
                        Button(sectionAllSelected ? "取消全选" : "全选") {
                            if sectionAllSelected {
                                selectedIds.subtract(sectionIds)
                            } else {
                                selectedIds.formUnion(sectionIds)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sectionAllSelected ? "取消全选" : "全选")\(artist)")
                    }
                }
                .plainListRow(insets: EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 12))

                ForEach(songs) { song in
                    songSelectRow(song)
                        .clearListRow(insets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowSeparatorTint(palette.separator)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var selectAllRow: some View {
        let allFilteredIds = selectableIds(filteredSongs)
        let allSelected = !allFilteredIds.isEmpty && allFilteredIds.isSubset(of: selectedIds)
        return HStack(spacing: 12) {
            Button {
                if allSelected {
                    selectedIds.subtract(allFilteredIds)
                } else {
                    selectedIds.formUnion(allFilteredIds)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(allSelected ? palette.accent : palette.textSecondary)
                    Text(allSelected ? "取消全选" : "全选 \(allFilteredIds.count) 首")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(allFilteredIds.isEmpty)

            Spacer()

            Button("反选") {
                selectedIds.formSymmetricDifference(allFilteredIds)
            }
            .font(.subheadline)
            .foregroundColor(palette.accent)
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.plain)
            .disabled(allFilteredIds.isEmpty)

            Text("已选 \(selectedIds.count) 首")
                .font(.footnote.monospacedDigit())
                .foregroundColor(palette.textSecondary)
        }
    }

    /// 已在歌单中的歌曲不可再选，并说明原因（交互设计文档 §5.3）
    private func songSelectRow(_ song: Song) -> some View {
        let isExisting = existingSongIds.contains(song.id)
        let isSelected = selectedIds.contains(song.id)
        return Button {
            if isSelected {
                selectedIds.remove(song.id)
            } else {
                selectedIds.insert(song.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isExisting ? "checkmark.circle" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundColor(isSelected ? palette.accent : palette.textSecondary)
                    .accessibilityHidden(true)

                CoverImageView(path: song.coverImagePath, size: 44, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body.weight(.medium))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(isExisting ? "已在歌单中" : "\(song.artist) · \(song.album)")
                        .font(.footnote)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(song.duration.formattedTime)
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
            .frame(minHeight: 56)
            .opacity(isExisting ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isExisting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(song.title)，\(song.artist)\(isExisting ? "，已在歌单中" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func loadData() async {
        allSongs = await libraryService.fetchAllSongs(sortBy: .artist, ascending: true)
        if let detail = await playlistService.fetchDetail(playlistId: playlistId) {
            existingSongIds = Set(detail.songs.map(\.id))
        }
        isLoading = false
    }

    private func addSelected() async {
        isSaving = true
        do {
            try await playlistService.addSongs(Array(selectedIds), to: playlistId)
            dismiss()
        } catch {
            snackbar.show(message: "添加歌曲失败，请重试")
        }
        isSaving = false
    }
}

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
                Divider().background(palette.separator)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if allSongs.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .foregroundColor(palette.iconSecondary)
                        Text("音乐库中暂无歌曲")
                            .foregroundColor(palette.textSecondary)
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
                        .foregroundColor(palette.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await addSelected() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("添加 (\(selectedIds.count))")
                        }
                    }
                    .foregroundColor(palette.primary)
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
        let excluded = existingSongIds
        Task.detached {
            let available = songs.filter { !excluded.contains($0.id) }
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

    private var songList: some View {
        List {
            if !filteredSongs.isEmpty {
                selectAllSection
            }

            ForEach(groupedByArtist, id: \.0) { artist, songs in
                Section {
                    ForEach(songs) { song in
                        songSelectRow(song)
                    }
                } header: {
                    let sectionIds = Set(songs.map(\.id))
                    let sectionAllSelected = sectionIds.isSubset(of: selectedIds)
                    HStack {
                        Text(artist)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        Button {
                            if sectionAllSelected {
                                selectedIds.subtract(sectionIds)
                            } else {
                                selectedIds.formUnion(sectionIds)
                            }
                        } label: {
                            Text(sectionAllSelected ? "取消全选" : "全选")
                                .font(.caption)
                                .foregroundColor(palette.primary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var selectAllSection: some View {
        let allFilteredIds = Set(filteredSongs.map(\.id))
        let allSelected = allFilteredIds.isSubset(of: selectedIds)
        return Section {
            HStack(spacing: 0) {
                Button {
                    if allSelected {
                        selectedIds.subtract(allFilteredIds)
                    } else {
                        selectedIds.formUnion(allFilteredIds)
                    }
                } label: {
                    HStack {
                        Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(allSelected ? palette.primary : palette.textTertiary)
                            .font(.title3)
                        Text(allSelected ? "取消全选" : "全选 (\(filteredSongs.count) 首)")
                            .foregroundColor(palette.textPrimary)
                    }
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    selectedIds.formSymmetricDifference(allFilteredIds)
                } label: {
                    Text("反选")
                        .font(.subheadline)
                        .foregroundColor(palette.primary)
                }
                .buttonStyle(.borderless)

                Spacer().frame(width: 16)

                Text("已选 \(selectedIds.count) 首")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(palette.surface)
        }
    }

    private func songSelectRow(_ song: Song) -> some View {
        Button {
            if selectedIds.contains(song.id) {
                selectedIds.remove(song.id)
            } else {
                selectedIds.insert(song.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedIds.contains(song.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedIds.contains(song.id) ? palette.primary : palette.textTertiary)
                    .font(.title3)

                CoverImageView(path: song.coverImagePath, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(song.duration.formattedTime)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.surface)
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

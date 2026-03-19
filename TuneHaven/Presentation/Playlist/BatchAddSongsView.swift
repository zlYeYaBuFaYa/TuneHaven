import SwiftUI

struct BatchAddSongsView: View {
    let playlistId: UUID

    @EnvironmentObject private var playlistService: PlaylistService
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
                            .font(.system(size: 48))
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
        .onChange(of: searchText) { _, newValue in
            searchDebouncer.send(newValue)
            if newValue.isEmpty { recomputeFiltered(query: "") }
        }
        .onChange(of: searchDebouncer.debouncedQuery) { _, query in
            recomputeFiltered(query: query)
        }
        .onChange(of: allSongs) { _, _ in recomputeFiltered(query: searchDebouncer.debouncedQuery) }
    }

    private func recomputeFiltered(query: String) {
        let available = allSongs.filter { !existingSongIds.contains($0.id) }
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
        filteredSongs = filtered
        let grouped = Dictionary(grouping: filtered) { $0.artist }
        groupedByArtist = grouped.sorted { $0.key < $1.key }
    }

    private var fixedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.textTertiary)
            TextField("搜索歌曲、艺术家、专辑", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(palette.textPrimary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.surfaceSecondary)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                    HStack {
                        Text(artist)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        Button {
                            let songIds = Set(songs.map(\.id))
                            let allSelected = songIds.isSubset(of: selectedIds)
                            if allSelected {
                                selectedIds.subtract(songIds)
                            } else {
                                selectedIds.formUnion(songIds)
                            }
                        } label: {
                            let songIds = Set(songs.map(\.id))
                            Text(songIds.isSubset(of: selectedIds) ? "取消全选" : "全选")
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
        Section {
            HStack(spacing: 0) {
                Button {
                    let allIds = Set(filteredSongs.map(\.id))
                    if allIds.isSubset(of: selectedIds) {
                        selectedIds.subtract(allIds)
                    } else {
                        selectedIds.formUnion(allIds)
                    }
                } label: {
                    HStack {
                        let allIds = Set(filteredSongs.map(\.id))
                        let allSelected = allIds.isSubset(of: selectedIds)
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
                    let allIds = Set(filteredSongs.map(\.id))
                    selectedIds.formSymmetricDifference(allIds)
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
        let repo = CoreDataSongRepository()
        allSongs = await repo.fetchAll(sortBy: .artist, ascending: true)
        if let detail = await playlistService.fetchDetail(playlistId: playlistId) {
            existingSongIds = Set(detail.songs.map(\.id))
        }
        isLoading = false
    }

    private func addSelected() async {
        isSaving = true
        try? await playlistService.addSongs(Array(selectedIds), to: playlistId)
        isSaving = false
        dismiss()
    }
}

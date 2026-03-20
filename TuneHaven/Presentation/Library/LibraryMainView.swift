import SwiftUI
import Combine

@MainActor
final class SearchDebouncer: ObservableObject {
    @Published var debouncedQuery = ""
    private let subject = PassthroughSubject<String, Never>()
    private var cancellable: AnyCancellable?

    init() {
        cancellable = subject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.debouncedQuery = query
            }
    }

    func send(_ query: String) {
        subject.send(query)
    }
}

struct LibraryMainView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var searchService: SearchService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.hasCustomBackground) private var hasCustomBg

    @StateObject private var searchDebouncer = SearchDebouncer()
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedTab: LibraryTab = .all
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var searchResult = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
    @AppStorage("song_sort_option") private var sortOptionRaw: Int = SongSortOption.title.rawValue
    @AppStorage("song_sort_ascending") private var isAscending: Bool = true
    @State private var formatFilter: AudioFormat = .all

    private var sortOptionBinding: Binding<SongSortOption> {
        Binding(
            get: { SongSortOption(rawValue: sortOptionRaw) ?? .title },
            set: { sortOptionRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            tabBar
            Divider()
                .background(palette.separator)

            if isSearchActive && !searchDebouncer.debouncedQuery.isEmpty {
                SearchResultView(
                    result: searchResult,
                    query: searchDebouncer.debouncedQuery,
                    tab: selectedTab,
                    onDeleteSong: { song in searchDeleteSong(song) },
                    onFavoriteSong: { song in searchFavoriteSong(song) },
                    onAddToPlaylist: { song in router.present(.addToPlaylist(songIds: [song.id])) }
                )
            } else if isSearchFieldFocused && searchText.isEmpty {
                searchHistoryView
            } else {
                libraryContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .adaptiveBackground()
        .navigationTitle("音乐库")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(hasCustomBg ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(palette.surface), for: .navigationBar)
        .onChange(of: searchDebouncer.debouncedQuery) { _, query in
            performSearch(query: query)
        }
        .onChange(of: searchText) { _, newValue in
            searchDebouncer.send(newValue)
            if newValue.isEmpty {
                searchDebouncer.debouncedQuery = ""
                searchResult = .empty
            }
            if !newValue.isEmpty {
                isSearchActive = true
            }
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused && searchText.isEmpty {
                Task { await searchService.fetchHistory(tab: selectedTab) }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if isSearchFieldFocused && searchText.isEmpty {
                Task { await searchService.fetchHistory(tab: newTab) }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.textTertiary)
            TextField("搜索歌曲、艺术家或专辑", text: $searchText)
                .focused($isSearchFieldFocused)
                .textFieldStyle(.plain)
                .foregroundColor(palette.textPrimary)
            if !searchText.isEmpty || isSearchFieldFocused {
                Button {
                    searchText = ""
                    isSearchActive = false
                    isSearchFieldFocused = false
                } label: {
                    if searchText.isEmpty {
                        Text("取消")
                            .font(.subheadline)
                            .foregroundColor(palette.accent)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(palette.textTertiary)
                    }
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

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.displayName)
                        .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? .white : palette.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    LinearGradient(
                                        colors: [palette.gradientStart, palette.gradientEnd],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                } else {
                                    palette.surfaceSecondary
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var libraryContent: some View {
        Group {
            switch selectedTab {
            case .all:
                AllSongsView(sortOption: sortOptionBinding, isAscending: $isAscending, formatFilter: $formatFilter)
            case .artist:
                ArtistListView()
            case .album:
                AlbumGridView()
            }
        }
        .id(selectedTab)
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    private var searchHistoryView: some View {
        List {
            if searchService.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(palette.iconSecondary)
                    Text("暂无搜索历史")
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(searchService.history) { item in
                        Button {
                            searchText = item.keyword
                            isSearchActive = true
                            isSearchFieldFocused = false
                            Task {
                                searchResult = await searchService.search(
                                    query: item.keyword, tab: selectedTab, allSongs: libraryService.songs
                                )
                                await searchService.saveHistory(keyword: item.keyword, tab: selectedTab)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(palette.iconSecondary)
                                    .font(.subheadline)
                                Text(item.keyword)
                                    .foregroundColor(palette.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.searchedAt.relativeDescription)
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                        }
                        .listRowBackground(palette.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    await searchService.deleteHistory(id: item.id)
                                    await searchService.fetchHistory(tab: selectedTab)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("搜索历史")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        Button {
                            Task {
                                await searchService.clearHistory(tab: selectedTab)
                                await searchService.fetchHistory(tab: selectedTab)
                            }
                        } label: {
                            Text("清空")
                                .font(.caption)
                                .foregroundColor(palette.accent)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else { return }
        Task {
            searchResult = await searchService.search(query: query, tab: selectedTab, allSongs: libraryService.songs)
            await searchService.saveHistory(keyword: query, tab: selectedTab)
        }
    }

    private func refreshSearch() {
        let query = searchDebouncer.debouncedQuery
        guard !query.isEmpty else { return }
        Task {
            searchResult = await searchService.search(query: query, tab: selectedTab, allSongs: libraryService.songs)
        }
    }

    private func searchDeleteSong(_ song: Song) {
        Task {
            guard let token = try? await libraryService.softDelete(songIds: [song.id]) else { return }
            refreshSearch()
            snackbar.show(
                message: "已删除《\(song.title)》",
                actionTitle: "撤销",
                action: {
                    Task {
                        try? await libraryService.undoDelete(token: token)
                        refreshSearch()
                    }
                },
                duration: 30
            )
        }
    }

    private func searchFavoriteSong(_ song: Song) {
        Task {
            try? await libraryService.toggleFavorite(songId: song.id)
            refreshSearch()
        }
    }
}

extension SearchResult {
    static let empty = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
}

private extension Date {
    static let shortDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd"
        return fmt
    }()

    var relativeDescription: String {
        let interval = -timeIntervalSinceNow
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        if interval < 604800 { return "\(Int(interval / 86400))天前" }
        return Self.shortDateFormatter.string(from: self)
    }
}

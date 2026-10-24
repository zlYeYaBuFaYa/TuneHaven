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
    @Namespace private var tabNamespace
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var searchResult = SearchResult.empty
    @State private var searchTask: Task<Void, Never>?
    @AppStorage(AppStorageKey.songSortOption) private var sortOptionRaw: Int = SongSortOption.title.rawValue
    @AppStorage(AppStorageKey.songSortAscending) private var isAscending: Bool = true
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
        .themeNavigationBarSurface(customMaterial: hasCustomBg)
        .onChange(of: searchDebouncer.debouncedQuery) { query in
            performSearch(query: query)
        }
        .onChange(of: searchText) { newValue in
            searchDebouncer.send(newValue)
            if newValue.isEmpty {
                searchDebouncer.debouncedQuery = ""
                searchResult = .empty
            }
            if !newValue.isEmpty {
                isSearchActive = true
            }
        }
        .onChange(of: isSearchFieldFocused) { focused in
            if focused && searchText.isEmpty {
                Task { await searchService.fetchHistory(tab: selectedTab) }
            }
        }
        .onChange(of: selectedTab) { newTab in
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
        HStack(spacing: 24) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.displayName)
                        .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? palette.primary : palette.textSecondary)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(palette.primary)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "tab_underline", in: tabNamespace)
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
        SearchHistoryView(tab: selectedTab) { keyword in
            searchText = keyword
            isSearchActive = true
            isSearchFieldFocused = false
            Task {
                searchResult = await searchService.search(
                    query: keyword, tab: selectedTab, allSongs: libraryService.songs
                )
                await searchService.saveHistory(keyword: keyword, tab: selectedTab)
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            let result = await searchService.search(query: query, tab: selectedTab, allSongs: libraryService.songs)
            guard !Task.isCancelled else { return }
            searchResult = result
            await searchService.saveHistory(keyword: query, tab: selectedTab)
        }
    }

    private func refreshSearch() {
        let query = searchDebouncer.debouncedQuery
        guard !query.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            let result = await searchService.search(query: query, tab: selectedTab, allSongs: libraryService.songs)
            guard !Task.isCancelled else { return }
            searchResult = result
        }
    }

    private func searchDeleteSong(_ song: Song) {
        Task {
            do {
                let token = try await libraryService.softDelete(songIds: [song.id])
                refreshSearch()
                snackbar.show(
                    message: "已删除《\(song.title)》",
                    actionTitle: "撤销",
                    action: {
                        Task {
                            do {
                                try await libraryService.undoDelete(token: token)
                            } catch {
                                snackbar.show(message: "撤销删除失败，请重试")
                            }
                            refreshSearch()
                        }
                    },
                    duration: 30
                )
            } catch {
                snackbar.show(message: "删除失败，请重试")
            }
        }
    }

    private func searchFavoriteSong(_ song: Song) {
        Task {
            do {
                try await libraryService.toggleFavorite(songId: song.id)
            } catch {
                snackbar.show(message: "收藏操作失败")
            }
            refreshSearch()
        }
    }
}



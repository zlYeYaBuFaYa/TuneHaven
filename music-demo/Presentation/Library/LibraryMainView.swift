import SwiftUI
import Combine

@MainActor
private final class SearchDebouncer: ObservableObject {
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
    @Environment(\.themePalette) private var palette

    @StateObject private var searchDebouncer = SearchDebouncer()
    @State private var selectedTab: LibraryTab = .all
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var searchResult = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
    @State private var sortOption: SongSortOption = .title
    @State private var formatFilter: AudioFormat = .all

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            tabBar
            Divider()
                .background(palette.separator)

            if isSearchActive && !searchDebouncer.debouncedQuery.isEmpty {
                SearchResultView(result: searchResult, query: searchDebouncer.debouncedQuery, tab: selectedTab)
            } else {
                libraryContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background)
        .navigationTitle("音乐库")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.surface, for: .navigationBar)
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
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.textTertiary)
            TextField("搜索歌曲、艺术家或专辑", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(palette.textPrimary)
            if !searchText.isEmpty {
                Button { searchText = ""; isSearchActive = false } label: {
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

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.displayName)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? palette.primary : palette.textSecondary)
                        Rectangle()
                            .fill(selectedTab == tab ? palette.primary : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var libraryContent: some View {
        Group {
            switch selectedTab {
            case .all:
                AllSongsView(sortOption: $sortOption, formatFilter: $formatFilter)
            case .artist:
                ArtistListView()
            case .album:
                AlbumGridView()
            }
        }
        .id(selectedTab)
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else { return }
        Task {
            searchResult = await searchService.search(query: query, tab: selectedTab, allSongs: libraryService.songs)
        }
    }
}

extension SearchResult {
    static let empty = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
}

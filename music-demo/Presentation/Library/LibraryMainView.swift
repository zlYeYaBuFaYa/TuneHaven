import SwiftUI
import Combine

struct LibraryMainView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var searchService: SearchService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    @State private var selectedTab: LibraryTab = .all
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var isSearchActive = false
    @State private var searchResult = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
    @State private var sortOption: SongSortOption = .title
    @State private var formatFilter: AudioFormat = .all

    // 防抖发布者（TDD Section 6.1 debounce 300ms）
    private let searchSubject = PassthroughSubject<String, Never>()

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            tabBar
            Divider()
                .background(palette.separator)

            if isSearchActive && !debouncedQuery.isEmpty {
                SearchResultView(result: searchResult, query: debouncedQuery, tab: selectedTab)
            } else {
                libraryContent
            }
        }
        .background(palette.background)
        .navigationTitle("音乐库")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(
            searchSubject
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .removeDuplicates()
        ) { query in
            debouncedQuery = query
            performSearch(query: query)
        }
        .onChange(of: searchText) { _, newValue in
            searchSubject.send(newValue)
            if newValue.isEmpty {
                debouncedQuery = ""
                searchResult = .empty
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
                .onTapGesture { isSearchActive = true }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch selectedTab {
        case .all:
            AllSongsView(sortOption: $sortOption, formatFilter: $formatFilter)
        case .artist:
            ArtistListView()
        case .album:
            AlbumGridView()
        case .playlist:
            EmptyView()
        }
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

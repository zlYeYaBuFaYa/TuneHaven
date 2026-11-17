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
    #if DEBUG
    @State private var selectedTab: LibraryTab = DebugLaunchRoute.libraryTab ?? .all
    #else
    @State private var selectedTab: LibraryTab = .all
    #endif
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
        .toolbar {
            // 与设置中的导入入口共用同一个导入方式选择（交互设计文档 §4.1、§10）
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.importFromFiles)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("导入音乐")
            }
        }
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

    /// 搜索框（docs/UI设计文档.md §6：高 44、圆角 15）。
    /// 清除只清空输入并保留焦点；「取消」退出搜索并收起键盘（交互设计文档 §4.2）。
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(palette.textSecondary)
                    .accessibilityHidden(true)
                TextField("搜索歌曲、艺术家、专辑", text: $searchText)
                    .focused($isSearchFieldFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .foregroundColor(palette.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(palette.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索内容")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(palette.surface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(palette.separator, lineWidth: 0.5)
            )

            if isSearchFieldFocused || isSearchActive {
                Button("取消") {
                    searchText = ""
                    isSearchActive = false
                    isSearchFieldFocused = false
                }
                .font(.body)
                .foregroundColor(palette.accent)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.15), value: isSearchFieldFocused)
    }

    /// 分段按钮：选中为主操作色胶囊（docs/UI设计文档.md §6：视觉高 37–40，命中区 44）
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? palette.onAction : palette.textSecondary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 38)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(palette.actionFill)
                                    .matchedGeometryEffect(id: "segment", in: tabNamespace)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
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



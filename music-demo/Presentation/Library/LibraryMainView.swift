import SwiftUI
import Combine

struct LibraryMainView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
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
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
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
            PlaylistContentView()
        case .favorites:
            FavoritesContentView()
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else { return }
        Task {
            searchResult = await searchService.search(query: query, tab: selectedTab, allSongs: libraryService.songs)
        }
    }
}

// MARK: - Playlist Content (embedded in library)
private struct PlaylistContentView: View {
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    private var systemPlaylists: [Playlist] {
        playlistService.playlists.filter { $0.isSystem }.sorted { $0.systemType.rawValue < $1.systemType.rawValue }
    }
    private var userPlaylists: [Playlist] {
        playlistService.playlists.filter { !$0.isSystem }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                ForEach(systemPlaylists) { playlist in
                    SystemPlaylistRow(playlist: playlist) {
                        switch playlist.systemType {
                        case .favorites:
                            router.navigate(to: .songList(title: "我喜欢", context: .favorites), in: .library)
                        case .recentlyPlayed:
                            router.navigate(to: .songList(title: "最近播放", context: .recentlyPlayed), in: .library)
                        default:
                            router.navigate(to: .playlistDetail(id: playlist.id), in: .library)
                        }
                    }
                    .listRowBackground(palette.surface)
                }
            }
            Section {
                if userPlaylists.isEmpty {
                    Text("暂无歌单，点击右上角「+」新建")
                        .font(.subheadline)
                        .foregroundColor(palette.textTertiary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(userPlaylists) { playlist in
                        Button {
                            router.navigate(to: .playlistDetail(id: playlist.id), in: .library)
                        } label: {
                            PlaylistRow(playlist: playlist)
                        }
                        .listRowBackground(palette.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { try? await playlistService.deletePlaylist(id: playlist.id) }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                router.present(.editPlaylist(id: playlist.id))
                            } label: { Label("编辑", systemImage: "pencil") }
                            .tint(palette.primary)
                        }
                    }
                    .onMove { src, dst in
                        var sorted = userPlaylists
                        sorted.move(fromOffsets: src, toOffset: dst)
                        Task { try? await playlistService.reorderPlaylists(orderedIds: sorted.map { $0.id }) }
                    }
                }
            } header: {
                HStack {
                    Text("我的歌单")
                        .foregroundColor(palette.textSecondary)
                    Spacer()
                    Button {
                        router.present(.createPlaylist)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundColor(palette.primary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .task { await playlistService.loadPlaylists() }
    }
}

// MARK: - Favorites Content (embedded in library)
private struct FavoritesContentView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var playback = PlaybackService.shared
    @Environment(\.themePalette) private var palette

    @State private var songs: [Song] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if songs.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "heart")
                        .font(.system(size: 48))
                        .foregroundColor(palette.iconSecondary)
                    Text("暂无收藏歌曲")
                        .foregroundColor(palette.textSecondary)
                    Text("播放歌曲时点击心形按钮即可收藏")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(songs) { song in
                        SongRow(
                            song: song,
                            isPlaying: playback.currentSong?.id == song.id,
                            onTap: {
                                if playback.currentSong?.id == song.id {
                                    router.openPlayer()
                                } else {
                                    Task {
                                        await playback.play(song: song, in: .allSongs(sortBy: .title))
                                        router.openPlayer()
                                    }
                                }
                            }
                        )
                        .listRowBackground(palette.surface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(palette.background)
            }
        }
        .task { await load() }
        .onReceive(libraryService.$songs) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        songs = await playlistService.fetchFavorites()
        isLoading = false
    }
}

extension SearchResult {
    static let empty = SearchResult(songs: [], artists: [], albums: [], totalSongCount: 0, totalArtistCount: 0, totalAlbumCount: 0)
}

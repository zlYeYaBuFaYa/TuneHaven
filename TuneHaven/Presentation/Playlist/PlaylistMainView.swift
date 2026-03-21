import SwiftUI

struct PlaylistMainView: View {
    @EnvironmentObject private var playlistService: PlaylistService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var groupService: PlaylistGroupService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    @State private var showGroupManage = false

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
                            router.navigate(to: .songList(title: "我喜欢", context: .favorites), in: .playlist)
                        case .recentlyPlayed:
                            router.navigate(to: .songList(title: "最近播放", context: .recentlyPlayed), in: .playlist)
                        default:
                            router.navigate(to: .playlistDetail(id: playlist.id), in: .playlist)
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
                            router.navigate(to: .playlistDetail(id: playlist.id), in: .playlist)
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
                Text("我的歌单")
                    .foregroundColor(palette.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
        .navigationTitle("歌单")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(palette.surface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    router.present(.createPlaylist)
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(palette.primary)
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showGroupManage = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundColor(palette.primary)
                }
            }
        }
        .task { await playlistService.loadPlaylists() }
        .onReceive(libraryService.$songs.dropFirst()) { _ in
            Task { await playlistService.loadPlaylists() }
        }
        .sheet(isPresented: $showGroupManage) {
            NavigationStack {
                PlaylistGroupView()
                    .environmentObject(groupService)
                    .environmentObject(playlistService)
                    .environmentObject(router)
                    .environment(\.themePalette, palette)
            }
        }
    }
}

struct SystemPlaylistRow: View {
    let playlist: Playlist
    let onTap: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: iconGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.textPrimary)
                    Text("\(playlist.songCount) 首")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.iconSecondary)
            }
        }
    }

    private var iconName: String {
        switch playlist.systemType {
        case .favorites: return "heart.fill"
        case .recentlyPlayed: return "clock.fill"
        default: return "music.note.list"
        }
    }

    private var iconGradientColors: [Color] {
        switch playlist.systemType {
        case .favorites: return [palette.gradientStart, palette.accent]
        case .recentlyPlayed: return [palette.secondary, palette.gradientEnd]
        default: return [palette.gradientStart, palette.gradientEnd]
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(path: playlist.coverImagePath, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text("\(playlist.songCount) 首")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.iconSecondary)
        }
    }
}

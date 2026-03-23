import SwiftUI

struct SearchResultView: View {
    let result: SearchResult
    let query: String
    let tab: LibraryTab
    var onDeleteSong: ((Song) -> Void)? = nil
    var onFavoriteSong: ((Song) -> Void)? = nil
    var onAddToPlaylist: ((Song) -> Void)? = nil

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.themePalette) private var palette
    @State private var showAllSongs = false
    @State private var showAllArtists = false
    @State private var showAllAlbums = false

    var body: some View {
        List {
            if !result.songs.isEmpty {
                Section("歌曲 (\(result.totalMatchCount))") {
                    ForEach(result.songs.prefix(showAllSongs ? result.songs.count : 10)) { song in
                        SongRow(
                            song: song,
                            isPlaying: playback.currentSong?.id == song.id,
                            onTap: {
                                Task {
                                    await playback.prepare(song: song, in: playContext(for: song))
                                    router.openPlayer()
                                }
                            },
                            onFavorite: onFavoriteSong != nil ? { onFavoriteSong?(song) } : nil,
                            onDelete: onDeleteSong != nil ? { onDeleteSong?(song) } : nil,
                            onAddToPlaylist: onAddToPlaylist != nil ? { onAddToPlaylist?(song) } : nil,
                            onInsertNext: { _ = playback.queue.insertNext(song) }
                        )
                        .listRowBackground(palette.surface)
                    }
                    if !showAllSongs && result.songs.count > 10 {
                        Button {
                            withAnimation { showAllSongs = true }
                        } label: {
                            Text("查看全部 \(result.totalMatchCount) 首歌曲")
                                .font(.subheadline)
                                .foregroundColor(palette.primary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            if !result.artists.isEmpty {
                Section("艺术家 (\(result.totalArtistCount))") {
                    ForEach(result.artists.prefix(showAllArtists ? result.artists.count : 5)) { artist in
                        Button {
                            router.navigate(to: .artistDetail(name: artist.name))
                        } label: {
                            HStack {
                                Text(artist.name)
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                Text("\(artist.songCount) 首")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                    if !showAllArtists && result.artists.count > 5 {
                        Button {
                            withAnimation { showAllArtists = true }
                        } label: {
                            Text("查看全部 \(result.totalArtistCount) 位艺术家")
                                .font(.subheadline)
                                .foregroundColor(palette.primary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            if !result.albums.isEmpty {
                Section("专辑 (\(result.totalAlbumCount))") {
                    ForEach(result.albums.prefix(showAllAlbums ? result.albums.count : 5)) { album in
                        Button {
                            router.navigate(to: .albumDetail(album: album.name, artist: album.artist))
                        } label: {
                            HStack(spacing: 12) {
                                CoverImageView(path: album.coverImagePath, size: 44)
                                VStack(alignment: .leading) {
                                    Text(album.name)
                                        .foregroundColor(palette.textPrimary)
                                    Text(album.artist)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                    if !showAllAlbums && result.albums.count > 5 {
                        Button {
                            withAnimation { showAllAlbums = true }
                        } label: {
                            Text("查看全部 \(result.totalAlbumCount) 张专辑")
                                .font(.subheadline)
                                .foregroundColor(palette.primary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            if result.songs.isEmpty && result.artists.isEmpty && result.albums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(palette.iconSecondary)
                    Text("未找到「\(query)」相关结果")
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }

    private func playContext(for song: Song) -> PlayContext {
        switch tab {
        case .artist:
            return .artist(name: song.artist)
        case .album:
            return .album(name: song.album, artist: song.artist)
        case .all:
            return .allSongs(sortBy: .title)
        }
    }
}

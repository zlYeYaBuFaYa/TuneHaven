import SwiftUI

struct SearchResultView: View {
    let result: SearchResult
    let query: String
    let tab: LibraryTab

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var playback = PlaybackService.shared
    @Environment(\.themePalette) private var palette

    var body: some View {
        List {
            if !result.songs.isEmpty {
                Section("歌曲 (\(result.totalSongCount))") {
                    ForEach(result.songs.prefix(10)) { song in
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
            }
            if !result.artists.isEmpty {
                Section("艺术家 (\(result.totalArtistCount))") {
                    ForEach(result.artists.prefix(5)) { artist in
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
                }
            }
            if !result.albums.isEmpty {
                Section("专辑 (\(result.totalAlbumCount))") {
                    ForEach(result.albums.prefix(5)) { album in
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
        .background(palette.background)
    }
}

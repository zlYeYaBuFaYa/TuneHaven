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
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @AppStorage(AppStorageKey.songSortOption) private var songSortOptionRaw: Int = SongSortOption.title.rawValue
    @State private var showAllSongs = false
    @State private var showAllArtists = false
    @State private var showAllAlbums = false

    var body: some View {
        List {
            if !result.songs.isEmpty {
                sectionTitle("歌曲", count: result.totalMatchCount)
                ForEach(result.songs.prefix(showAllSongs ? result.songs.count : 10)) { song in
                    SongRow(
                        song: song,
                        isPlaying: playback.currentSong?.id == song.id,
                        isPlaybackActive: playback.isPlaying,
                        onTap: {
                            Task {
                                await playback.play(song: song, in: playContext(for: song))
                                router.openPlayer()
                            }
                        },
                        onFavorite: onFavoriteSong != nil ? { onFavoriteSong?(song) } : nil,
                        onDelete: onDeleteSong != nil ? { onDeleteSong?(song) } : nil,
                        onAddToPlaylist: onAddToPlaylist != nil ? { onAddToPlaylist?(song) } : nil,
                        onInsertNext: { SongQueueHelper.insertNext(song: song, playback: playback, snackbar: snackbar) }
                    )
                    .clearListRow()
                    .listRowSeparatorTint(palette.separator)
                }
                if !showAllSongs && result.songs.count > 10 {
                    showAllButton("查看全部 \(result.totalMatchCount) 首歌曲") { showAllSongs = true }
                }
            }
            if !result.artists.isEmpty {
                sectionTitle("艺术家", count: result.totalArtistCount)
                ForEach(result.artists.prefix(showAllArtists ? result.artists.count : 5)) { artist in
                    Button {
                        router.navigate(to: .artistDetail(name: artist.name))
                    } label: {
                        HStack(spacing: 12) {
                            ArtistAvatar(name: artist.name, size: 45)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                    .lineLimit(1)
                                Text("\(artist.songCount) 首")
                                    .font(.footnote)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(palette.textSecondary)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("艺术家：\(artist.name)，\(artist.songCount) 首")
                    .accessibilityAddTraits(.isButton)
                    .clearListRow(insets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparatorTint(palette.separator)
                }
                if !showAllArtists && result.artists.count > 5 {
                    showAllButton("查看全部 \(result.totalArtistCount) 位艺术家") { showAllArtists = true }
                }
            }
            if !result.albums.isEmpty {
                sectionTitle("专辑", count: result.totalAlbumCount)
                ForEach(result.albums.prefix(showAllAlbums ? result.albums.count : 5)) { album in
                    Button {
                        router.navigate(to: .albumDetail(album: album.name, artist: album.artist))
                    } label: {
                        AlbumRow(album: album, subtitle: album.artist)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("专辑：\(album.name)，\(album.artist)")
                    .accessibilityAddTraits(.isButton)
                    .clearListRow(insets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparatorTint(palette.separator)
                }
                if !showAllAlbums && result.albums.count > 5 {
                    showAllButton("查看全部 \(result.totalAlbumCount) 张专辑") { showAllAlbums = true }
                }
            }
            if result.songs.isEmpty && result.artists.isEmpty && result.albums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(palette.accent)
                        .accessibilityHidden(true)
                    Text("没有找到「\(query)」相关音乐")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("试试拼音首字母")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .plainListRow()
            }

            Color.clear.frame(height: MiniPlayerLayout.listBottomPadding)
                .plainListRow(insets: EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        ListSectionTitle(title: title, count: count)
            .plainListRow(insets: EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))
    }

    private func showAllButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plainListRow()
    }

    private func playContext(for song: Song) -> PlayContext {
        switch tab {
        case .artist:
            return .artist(name: song.artist)
        case .album:
            return .album(name: song.album, artist: song.artist)
        case .all:
            let sortBy = SongSortOption(rawValue: songSortOptionRaw) ?? .title
            return .allSongs(sortBy: sortBy)
        }
    }
}

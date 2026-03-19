import SwiftUI

struct AlbumGridView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    @State private var albums: [AlbumGroup] = []
    @State private var isLoading = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if albums.isEmpty {
                EmptyStateView(icon: "square.grid.2x2", title: "暂无专辑", subtitle: "导入音乐后将按专辑分组显示")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(albums) { album in
                            Button {
                                router.navigate(to: .albumDetail(album: album.name, artist: album.artist))
                            } label: {
                                AlbumGridCell(album: album)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .adaptiveBackground()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        albums = await libraryService.fetchSongsByAlbum()
        isLoading = false
    }
}

struct AlbumGridCell: View {
    let album: AlbumGroup
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                CoverImageView(path: album.coverImagePath, size: geo.size.width, cornerRadius: 10)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(album.name)
                .font(.subheadline.weight(.medium))
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Text(album.artist)
                .font(.caption)
                .foregroundColor(palette.textSecondary)
                .lineLimit(1)
        }
    }
}

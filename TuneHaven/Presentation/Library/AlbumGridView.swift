import SwiftUI

/// 专辑页（docs/UI设计文档.md §7.1；交互设计文档 §4.1）：「最近添加」横向陈列 + 全部专辑网格。
/// 「最近添加」按专辑内最新导入歌曲时间排序，只用本地数据。
struct AlbumGridView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var albums: [AlbumGroup] = []
    @State private var recentAlbums: [AlbumGroup] = []
    @State private var isLoading = false

    private static let recentLimit = 6

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }

    var body: some View {
        Group {
            if isLoading && albums.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if albums.isEmpty {
                EmptyStateView(icon: "square.stack", title: "还没有专辑", subtitle: "导入音乐后会按专辑整理")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if recentAlbums.count > 1 {
                            recentSection
                        }
                        allSection
                    }
                    .padding(.top, 8)
                    .padding(.bottom, MiniPlayerLayout.listBottomPadding)
                }
            }
        }
        .task { await load() }
        .onChange(of: libraryService.songs) { _ in
            Task { await load() }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("最近添加")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(recentAlbums) { album in
                        albumButton(album, width: 160)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var allSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sectionTitle("全部专辑")
                Text("\(albums.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
            .padding(.trailing, 20)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(albums) { album in
                    albumButton(album, width: nil)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(palette.textPrimary)
            .padding(.leading, 20)
            .accessibilityAddTraits(.isHeader)
    }

    private func albumButton(_ album: AlbumGroup, width: CGFloat?) -> some View {
        Button {
            router.navigate(to: .albumDetail(album: album.name, artist: album.artist))
        } label: {
            AlbumGridCell(album: album)
                .frame(width: width)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        recentAlbums = LibraryGrouping.recentlyAddedAlbums(from: libraryService.songs, limit: Self.recentLimit)
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
                CoverImageView(path: album.coverImagePath, size: geo.size.width, cornerRadius: 17)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(album.name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Text("\(album.artist) · \(album.songCount) 首")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("专辑：\(album.name)，\(album.artist)，\(album.songCount) 首")
    }
}

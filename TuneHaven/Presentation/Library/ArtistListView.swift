import SwiftUI

struct ArtistListView: View {
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette

    @State private var artists: [ArtistGroup] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if artists.isEmpty {
                emptyState
            } else {
                List(artists) { artist in
                    Button {
                        router.navigate(to: .artistDetail(name: artist.name))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(artist.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(palette.textPrimary)
                                Text("\(artist.songCount) 首 · \(artist.albumCount) 张专辑")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.iconSecondary)
                        }
                    }
                    .listRowBackground(palette.surface)
                    .listRowSeparatorTint(palette.separator)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task { await load() }
        .onChange(of: libraryService.songs.count) { _, _ in
            Task { await load() }
        }
    }

    private var emptyState: some View {
        EmptyStateView(icon: "person.2", title: "暂无艺术家", subtitle: "导入音乐后将按艺术家分组显示")
    }

    private func load() async {
        isLoading = true
        artists = await libraryService.fetchSongsByArtist()
        isLoading = false
    }
}

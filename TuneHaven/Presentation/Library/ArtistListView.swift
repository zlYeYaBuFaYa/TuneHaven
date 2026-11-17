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
                List {
                    ForEach(artists) { artist in
                        Button {
                            router.navigate(to: .artistDetail(name: artist.name))
                        } label: {
                            HStack(spacing: 12) {
                                ArtistAvatar(name: artist.name)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(artist.name)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(palette.textPrimary)
                                        .lineLimit(1)
                                    Text("\(artist.songCount) 首 · \(artist.albumCount) 张专辑")
                                        .font(.footnote)
                                        .foregroundColor(palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(palette.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("艺术家：\(artist.name)，\(artist.songCount) 首，\(artist.albumCount) 张专辑")
                        .accessibilityAddTraits(.isButton)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(palette.separator)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                    Color.clear
                        .frame(height: MiniPlayerLayout.listBottomPadding)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task { await load() }
        .onChange(of: libraryService.songs.count) { _ in
            Task { await load() }
        }
    }

    private var emptyState: some View {
        EmptyStateView(icon: "person.2", title: "还没有艺术家", subtitle: "导入音乐后会按艺术家整理")
    }

    private func load() async {
        isLoading = true
        artists = await libraryService.fetchSongsByArtist()
        isLoading = false
    }
}

/// 艺术家头像：取名字首字，主题光晕渐变底。纯装饰，不进入可访问树。
struct ArtistAvatar: View {
    let name: String
    var size: CGFloat = 45
    @Environment(\.themePalette) private var palette

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(palette.textPrimary)
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    LinearGradient(colors: [palette.glowA, palette.glowB], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            )
            .overlay(Circle().stroke(palette.separator, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

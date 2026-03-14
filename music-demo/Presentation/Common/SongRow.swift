import SwiftUI

struct SongRow: View {
    let song: Song
    var isPlaying: Bool = false
    var showIndex: Int? = nil
    var onTap: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onAddToPlaylist: (() -> Void)? = nil
    var onInsertNext: (() -> Void)? = nil

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            if let idx = showIndex {
                Text("\(idx)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(palette.textTertiary)
                    .frame(width: 22, alignment: .center)
            }

            CoverImageView(path: song.coverImagePath, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(song.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isPlaying ? palette.primary : palette.textPrimary)
                        .lineLimit(1)
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(palette.primary)
                            .symbolEffect(.variableColor.iterative)
                    }
                }
                HStack(spacing: 4) {
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                    if !song.album.isEmpty && song.album != "未知专辑" {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                        Text(song.album)
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(song.duration.formattedTime)
                .font(.caption.monospacedDigit())
                .foregroundColor(palette.textTertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .swipeActions(edge: .trailing) {
            if let del = onDelete {
                Button(role: .destructive, action: del) {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if let fav = onFavorite {
                Button(action: fav) {
                    Label(song.isFavorite ? "取消喜欢" : "喜欢", systemImage: song.isFavorite ? "heart.slash" : "heart")
                }
                .tint(SemanticColor.danger)
            }
        }
        .contextMenu {
            contextMenuContent
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let fav = onFavorite {
            Button(action: fav) {
                Label(song.isFavorite ? "取消喜欢" : "添加喜欢", systemImage: song.isFavorite ? "heart.slash" : "heart")
            }
        }
        if let next = onInsertNext {
            Button(action: next) {
                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
        }
        if let addToPlaylist = onAddToPlaylist {
            Button(action: addToPlaylist) {
                Label("添加到歌单", systemImage: "plus.circle")
            }
        }
        Divider()
        if let del = onDelete {
            Button(role: .destructive, action: del) {
                Label("删除歌曲", systemImage: "trash")
            }
        }
    }
}

extension TimeInterval {
    var formattedTime: String {
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

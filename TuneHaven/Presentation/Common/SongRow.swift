import SwiftUI

/// 歌曲行（docs/UI设计文档.md §6、§7.1；交互设计文档 §4.3）：封面、歌名、艺术家、正在播放标记、更多。
/// 右滑喜欢、左滑删除／移出，长按与「更多」按钮提供同等操作，不只依赖手势。
struct SongRow: View {
    let song: Song
    /// 是否为当前歌曲
    var isPlaying: Bool = false
    /// 当前歌曲是否正在出声。暂停时播放标记静止
    var isPlaybackActive: Bool = false
    var showIndex: Int? = nil
    var onTap: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    /// 删除动作的文案：音乐库为「从音乐库删除」，歌单内为「移出歌单」
    var deleteTitle: String = "从音乐库删除"
    var onAddToPlaylist: (() -> Void)? = nil
    var onInsertNext: (() -> Void)? = nil

    @Environment(\.themePalette) private var palette

    private var hasMenuActions: Bool {
        onFavorite != nil || onDelete != nil || onAddToPlaylist != nil || onInsertNext != nil
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 12) {
                    if let idx = showIndex {
                        Text("\(idx)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(palette.textSecondary)
                            .frame(minWidth: 22, alignment: .center)
                    }

                    CoverImageView(path: song.coverImagePath, size: 45, cornerRadius: 10)
                        .opacity(song.isAudioMissing ? 0.5 : 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.body.weight(.medium))
                            .foregroundColor(song.isAudioMissing ? palette.textSecondary : palette.textPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if isPlaying {
                        WaveformIndicator(color: palette.accent, isAnimating: isPlaybackActive)
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)

            if hasMenuActions {
                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作：\(song.title)")
            }
        }
        .swipeActions(edge: .trailing) {
            if let del = onDelete {
                Button(role: .destructive, action: del) {
                    Label(deleteTitle, systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if let fav = onFavorite {
                Button(action: fav) {
                    Label(song.isFavorite ? "取消喜欢" : "喜欢", systemImage: song.isFavorite ? "heart.slash" : "heart")
                }
                .tint(palette.accent)
            }
        }
        .contextMenu {
            menuContent
        }
    }

    private var subtitle: String {
        if song.isAudioMissing { return "未找到音频" }
        if song.album.isEmpty || song.album == SongDefaults.unknownAlbum { return song.artist }
        return "\(song.artist) · \(song.album)"
    }

    private var accessibilityText: String {
        var parts = [song.title, song.artist]
        if song.isAudioMissing { parts.append("未找到音频") }
        if song.isFavorite { parts.append("已喜欢") }
        if isPlaying { parts.append(isPlaybackActive ? "正在播放" : "已暂停") }
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private var menuContent: some View {
        if let fav = onFavorite {
            Button(action: fav) {
                Label(song.isFavorite ? "取消喜欢" : "喜欢", systemImage: song.isFavorite ? "heart.slash" : "heart")
            }
        }
        if let next = onInsertNext {
            Button(action: next) {
                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
        }
        if let addToPlaylist = onAddToPlaylist {
            Button(action: addToPlaylist) {
                Label("添加到歌单", systemImage: "text.badge.plus")
            }
        }
        if onDelete != nil && (onFavorite != nil || onInsertNext != nil || onAddToPlaylist != nil) {
            Divider()
        }
        if let del = onDelete {
            Button(role: .destructive, action: del) {
                Label(deleteTitle, systemImage: "trash")
            }
        }
    }
}

import SwiftUI

/// 统一空状态占位组件（TDD §1.2 Common）
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(palette.accent)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.onAction)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(palette.actionFill))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 常用预设

extension EmptyStateView {
    static func noSongs(onImport: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "music.note.list",
            title: "还没有音乐",
            subtitle: "把喜欢的音乐带进来",
            actionTitle: "导入音乐",
            action: onImport
        )
    }

    static func noSearchResults(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "没有找到相关音乐",
            subtitle: "试试拼音首字母"
        )
    }

    static func noPlaylists(onCreate: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "music.note.house",
            title: "还没有歌单",
            subtitle: "创建歌单来整理你的音乐",
            actionTitle: "创建第一个歌单",
            action: onCreate
        )
    }

    static func noFavorites() -> EmptyStateView {
        EmptyStateView(
            icon: "heart",
            title: "还没有收藏",
            subtitle: "长按歌曲选择「加入我喜欢」"
        )
    }

    static func noRecentPlays() -> EmptyStateView {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "暂无播放记录",
            subtitle: "播放过的歌曲会出现在这里"
        )
    }

    static func noLyrics() -> EmptyStateView {
        EmptyStateView(
            icon: "text.alignleft",
            title: "暂无歌词",
            subtitle: "支持 .lrc 格式，可在歌曲详情中添加"
        )
    }
}

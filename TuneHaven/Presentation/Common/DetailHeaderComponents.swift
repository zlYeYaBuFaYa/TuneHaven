import SwiftUI

/// 详情页「播放全部／随机播放」按钮对（docs/UI设计文档.md §7.5：沿用主操作色与次级表面）
struct DetailPlayButtons: View {
    let isEnabled: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("播放全部", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.onAction)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(palette.actionFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onShuffle) {
                Label("随机播放", systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(palette.surface.opacity(0.7)))
                    .overlay(Capsule().stroke(palette.separator, lineWidth: 0.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// 列表分区标题：「标题 N」，与音乐库首页「所有歌曲 N」一致
struct ListSectionTitle: View {
    let title: String
    var count: Int? = nil

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(palette.textPrimary)
            if let count {
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// 柔光背景上的透明列表行
    func clearListRow(insets: EdgeInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8)) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(insets)
    }

    /// 无分隔线的透明列表行（头部、标题、留白）
    func plainListRow(insets: EdgeInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(insets)
    }
}

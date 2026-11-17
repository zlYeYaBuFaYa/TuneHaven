import SwiftUI

/// 页内搜索框，与音乐库首页搜索框同一外观：高 44、圆角 15、半透明表面（docs/UI设计文档.md §6）。
/// 清除只清空输入，焦点保留
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.themePalette) private var palette
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(palette.textSecondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .foregroundColor(palette.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索内容")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(palette.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(palette.separator, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

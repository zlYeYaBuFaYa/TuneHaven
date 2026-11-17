import SwiftUI

struct SearchHistoryView: View {
    let tab: LibraryTab
    let onSelect: (String) -> Void

    @EnvironmentObject private var searchService: SearchService
    @Environment(\.themePalette) private var palette

    @State private var showClearConfirm = false

    var body: some View {
        List {
            if searchService.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(palette.accent)
                        .accessibilityHidden(true)
                    Text("暂无搜索历史")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .plainListRow()
            } else {
                HStack {
                    ListSectionTitle(title: "最近搜索")
                    Button("清空") { showClearConfirm = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.plain)
                }
                .plainListRow(insets: EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 12))

                ForEach(searchService.history) { item in
                    Button {
                        onSelect(item.keyword)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "clock")
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.keyword)
                                    .font(.body)
                                    .foregroundColor(palette.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(item.searchedAt.relativeDescription)
                                    .font(.footnote)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left")
                                .font(.footnote)
                                .foregroundColor(palette.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("再次搜索")
                    .clearListRow(insets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparatorTint(palette.separator)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await searchService.deleteHistory(id: item.id)
                                await searchService.fetchHistory(tab: tab)
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }

                Text("历史记录按当前分类（全部、艺术家、专辑）分别保存")
                    .font(.footnote)
                    .foregroundColor(palette.textSecondary)
                    .padding(.top, 8)
                    .plainListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .confirmationDialog("清空搜索历史？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                Task {
                    await searchService.clearHistory(tab: tab)
                    await searchService.fetchHistory(tab: tab)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清空当前分类的搜索历史")
        }
    }
}

import SwiftUI

struct SearchHistoryView: View {
    let tab: LibraryTab
    let onSelect: (String) -> Void

    @EnvironmentObject private var searchService: SearchService
    @Environment(\.themePalette) private var palette

    var body: some View {
        List {
            if searchService.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(palette.iconSecondary)
                    Text("暂无搜索历史")
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(searchService.history) { item in
                        Button {
                            onSelect(item.keyword)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "clock")
                                    .foregroundColor(palette.iconSecondary)
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.keyword)
                                        .font(.body)
                                        .foregroundColor(palette.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(item.searchedAt.relativeDescription)
                                        .font(.caption)
                                        .foregroundColor(palette.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(palette.surface)
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
                } header: {
                    HStack {
                        Text("搜索历史")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        Button {
                            Task {
                                await searchService.clearHistory(tab: tab)
                                await searchService.fetchHistory(tab: tab)
                            }
                        } label: {
                            Text("清空")
                                .font(.caption)
                                .foregroundColor(palette.accent)
                        }
                    }
                } footer: {
                    Text("历史记录按当前标签页（全部、艺术家、专辑）分别保存。")
                        .font(.caption2)
                        .foregroundColor(palette.textTertiary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .adaptiveBackground()
    }
}

import SwiftUI

struct SettingsStorageSection: View {
    @EnvironmentObject private var searchService: SearchService
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool
    @Binding var currentCacheSize: String
    @Binding var showClearHistoryConfirm: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                cacheSizeRow
                clearHistoryRow
            } label: {
                Label {
                    Text("存储与隐私")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "externaldrive")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    private var cacheSizeRow: some View {
        HStack {
            Label("封面占用", systemImage: "photo.stack")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text(currentCacheSize)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
        }
        .listRowBackground(listRowBg)
    }

    private var clearHistoryRow: some View {
        Button {
            showClearHistoryConfirm = true
        } label: {
            Label("清除搜索记录", systemImage: "magnifyingglass")
                .font(.subheadline)
                .foregroundColor(SemanticColor.danger)
        }
        .listRowBackground(listRowBg)
        .confirmationDialog("清除搜索记录", isPresented: $showClearHistoryConfirm) {
            Button("清除", role: .destructive) {
                Task { await searchService.clearHistory() }
            }
        } message: {
            Text("将清除所有搜索历史记录")
        }
    }
}

import SwiftUI

struct SettingsStorageSection: View {
    @EnvironmentObject private var searchService: SearchService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool
    @Binding var cacheLimitMB: Int
    @Binding var currentCacheSize: String
    @Binding var showClearCacheConfirm: Bool
    @Binding var showClearHistoryConfirm: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                cacheSizeRow
                cacheLimitRow
                clearCacheRow
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
            Label("封面缓存占用", systemImage: "photo.stack")
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text(currentCacheSize)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
        }
        .listRowBackground(listRowBg)
    }

    private var cacheLimitRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("最大缓存限制")
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Text("\(cacheLimitMB) MB")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
            Slider(value: Binding(
                get: { Double(cacheLimitMB) },
                set: { cacheLimitMB = Int($0) }
            ), in: 50...300, step: 50)
            .tint(palette.primary)
            .onChange(of: cacheLimitMB) { _, newValue in
                libraryService.imageCache.setCacheLimit(newValue)
            }
        }
        .listRowBackground(listRowBg)
    }

    private var clearCacheRow: some View {
        Button {
            showClearCacheConfirm = true
        } label: {
            Label("清理封面缓存", systemImage: "trash")
                .font(.subheadline)
                .foregroundColor(SemanticColor.danger)
        }
        .listRowBackground(listRowBg)
        .confirmationDialog("清理缓存", isPresented: $showClearCacheConfirm) {
            Button("清理", role: .destructive) {
                Task {
                    await libraryService.imageCache.clearAll()
                    await calculateCacheSize()
                }
            }
        } message: {
            Text("将清除所有封面图片缓存，下次加载时会重新生成")
        }
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

    private func calculateCacheSize() async {
        let bytes = await libraryService.imageCache.cacheSizeAsync()
        let mb = Double(bytes) / 1024 / 1024
        currentCacheSize = mb < 1
            ? String(format: "%.0f KB", Double(bytes) / 1024)
            : String(format: "%.1f MB", mb)
    }
}

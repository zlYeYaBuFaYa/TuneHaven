import SwiftUI

struct SettingsImportSection: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool
    @Binding var showDocumentPicker: Bool
    @Binding var activeSheet: SettingsView.SettingsSheet?

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                importRow(icon: "folder", title: "文件导入", subtitle: "从 Files 导入 MP3, M4A 等格式") {
                    showDocumentPicker = true
                }

                importRow(icon: "music.note.house", title: "从 Apple Music 资料库导入", subtitle: "扫描设备上已下载的本地音乐") {
                    activeSheet = .appleMusicImport
                }

                importRow(icon: "cloud", title: "云盘导入", subtitle: "从百度网盘等云盘导入音乐") {
                    activeSheet = .cloudDriveImport
                }

                importRow(icon: "wifi", title: "WiFi 传输", subtitle: "通过浏览器从电脑无线传输音乐") {
                    activeSheet = .wifiTransfer
                }

                importRow(
                    icon: "server.rack",
                    title: "WebDAV 导入",
                    subtitle: subscriptionService.canAccess(.webDAVImport)
                        ? "从坚果云、NAS 等 WebDAV 服务器导入"
                        : "Premium 专属功能",
                    isLocked: !subscriptionService.canAccess(.webDAVImport)
                ) {
                    if subscriptionService.canAccess(.webDAVImport) {
                        activeSheet = .webDAVImport
                    } else {
                        router.present(.paywall(feature: .webDAVImport))
                    }
                }
            } label: {
                Label {
                    Text("导入音乐")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "square.and.arrow.down")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    private func importRow(icon: String, title: String, subtitle: String, isLocked: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isLocked ? palette.textTertiary : palette.textSecondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(isLocked ? palette.textTertiary : palette.primary)
            }
        }
        .listRowBackground(listRowBg)
    }
}

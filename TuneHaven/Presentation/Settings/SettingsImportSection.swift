import SwiftUI

struct SettingsImportSection: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool
    @Binding var showDocumentPicker: Bool
    @Binding var showAppleMusicImport: Bool
    @Binding var showCloudDriveImport: Bool
    @Binding var showWifiTransfer: Bool
    @Binding var showWebDAVImport: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                importRow(icon: "folder", title: "文件导入", subtitle: "从 Files 导入 MP3, M4A 等格式") {
                    showDocumentPicker = true
                }

                importRow(icon: "music.note.house", title: "从 Apple Music 资料库导入", subtitle: "扫描设备上已下载的本地音乐") {
                    showAppleMusicImport = true
                }

                importRow(icon: "cloud", title: "云盘导入", subtitle: "从百度网盘等云盘导入音乐") {
                    showCloudDriveImport = true
                }

                importRow(icon: "wifi", title: "WiFi 传输", subtitle: "通过浏览器从电脑无线传输音乐") {
                    showWifiTransfer = true
                }

                importRow(icon: "server.rack", title: "WebDAV 导入", subtitle: "从坚果云、NAS 等 WebDAV 服务器导入") {
                    showWebDAVImport = true
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

    private func importRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(palette.primary)
            }
        }
        .listRowBackground(listRowBg)
    }
}

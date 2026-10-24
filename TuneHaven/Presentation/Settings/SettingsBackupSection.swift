import SwiftUI

struct SettingsBackupSection: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg
    @EnvironmentObject private var backupService: BackupRestoreService

    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                row(
                    icon: "square.and.arrow.up",
                    title: "导出备份",
                    subtitle: "打包曲库与偏好，分享到文件 App"
                ) {
                    backupService.presentExport()
                }
                row(
                    icon: "square.and.arrow.down",
                    title: "从备份恢复",
                    subtitle: "合并、替换曲库，或只恢复偏好"
                ) {
                    backupService.presentRestore(url: nil)
                }
            } label: {
                Label {
                    Text("备份与恢复")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "archivebox")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    private func row(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
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

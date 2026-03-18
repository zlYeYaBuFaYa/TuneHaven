import SwiftUI

struct SettingsAboutSection: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                infoRow("支持格式", "MP3 / M4A / AAC / WAV / ALAC")
                infoRow("最大文件", "500 MB / 首")
                infoRow("数据存储", "iTunes 文件共享 / iCloud 备份")
            } label: {
                Label {
                    Text("关于")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "info.circle")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(listRowBg)
    }
}

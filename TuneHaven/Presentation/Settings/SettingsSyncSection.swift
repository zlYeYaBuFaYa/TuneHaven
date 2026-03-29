import SwiftUI

struct SettingsSyncSection: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var activeSheet: SettingsView.SettingsSheet?

    var body: some View {
        Section {
            Button {
                activeSheet = .syncTransfer
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("同步与传输")
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                        Text("导出歌曲和歌单，或从其他设备导入")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                } icon: {
                    SettingsSectionIcon(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .listRowBackground(listRowBg)
        }
    }
}

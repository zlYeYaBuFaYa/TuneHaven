import SwiftUI

struct SettingsShareSection: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool
    @Binding var activeSheet: SettingsView.SettingsSheet?

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                shareRow(
                    icon: "square.and.arrow.up",
                    title: "发送歌曲 / 歌单",
                    subtitle: "选择内容，生成二维码供对方扫描"
                ) {
                    activeSheet = .shareSend
                }

                shareRow(
                    icon: "qrcode.viewfinder",
                    title: "扫码接收",
                    subtitle: "扫描对方二维码，直接接收歌曲和歌单"
                ) {
                    activeSheet = .shareReceive
                }
            } label: {
                Label {
                    Text("分享")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "qrcode")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    private func shareRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
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

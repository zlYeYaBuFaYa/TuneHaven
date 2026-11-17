import SwiftUI

struct SettingsImportSection: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(MusicImportSource.allCases) { source in
                    Button {
                        router.present(.importFromSource(source))
                    } label: {
                        ImportSourceLabel(source: source, locked: source == .webDAV && !subscriptionService.canAccess(.webDAVImport))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(listRowBg)
                    .accessibilityIdentifier("settings.import.\(source.rawValue)")
                }
            } label: {
                Label { Text("导入音乐").foregroundColor(palette.textPrimary) } icon: {
                    SettingsSectionIcon(systemName: "square.and.arrow.down")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }
}

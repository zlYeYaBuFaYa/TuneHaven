import SwiftUI

struct SettingsSectionIcon: View {
    let systemName: String
    @Environment(\.themePalette) private var palette

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(palette.accent)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.tagBackground)
            )
            .accessibilityHidden(true)
    }
}

struct SettingsListRowBackground: EnvironmentKey {
    static let defaultValue: Color = Color(uiColor: .secondarySystemGroupedBackground)
}

extension EnvironmentValues {
    var settingsListRowBg: Color {
        get { self[SettingsListRowBackground.self] }
        set { self[SettingsListRowBackground.self] = newValue }
    }
}

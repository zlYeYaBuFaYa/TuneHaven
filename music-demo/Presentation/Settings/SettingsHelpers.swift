import SwiftUI

struct SettingsSectionIcon: View {
    let systemName: String
    @Environment(\.themePalette) private var palette

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline)
            .foregroundColor(palette.primaryDark)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.highlight)
            )
    }
}

struct SettingsListRowBackground: EnvironmentKey {
    static let defaultValue: Color = .clear
}

extension EnvironmentValues {
    var settingsListRowBg: Color {
        get { self[SettingsListRowBackground.self] }
        set { self[SettingsListRowBackground.self] = newValue }
    }
}

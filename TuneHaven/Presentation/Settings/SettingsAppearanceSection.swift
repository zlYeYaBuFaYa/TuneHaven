import SwiftUI

struct SettingsAppearanceSection: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                themeStyleRow
            } label: {
                Label {
                    Text("外观")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "paintbrush")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    // MARK: - Theme Style

    private var themeStyleRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主题风格")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(themeManager.allAvailableThemes) { style in
                    let isLocked = themeManager.isPremiumTheme(style)
                        && !subscriptionService.canAccess(.premiumTheme)
                    Button {
                        if isLocked {
                            router.present(.paywall(feature: .premiumTheme))
                        } else {
                            themeManager.setTheme(style)
                        }
                    } label: {
                        themeCard(style: style, isLocked: isLocked)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(listRowBg)
    }

    private func themeCard(style: ThemeStyle, isLocked: Bool = false) -> some View {
        let isSelected = themeManager.currentStyle.id == style.id
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [style.previewGradient.start, style.previewGradient.end],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 44)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(style.palette.onPrimary.opacity(0.8))
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(style.palette.onPrimary)
                        .padding(4)
                        .background(Circle().fill(style.palette.surface.opacity(0.3)))
                }
            }
            Text(style.displayName)
                .font(.caption2)
                .foregroundColor(isSelected ? palette.primary : palette.textSecondary)
                .lineLimit(1)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? palette.primary.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? palette.primary : Color.clear, lineWidth: 1.5)
        )
    }

}

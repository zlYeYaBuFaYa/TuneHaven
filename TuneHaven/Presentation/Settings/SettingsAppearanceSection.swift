import SwiftUI

struct SettingsAppearanceSection: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            // 辅助功能字号下改单列
            let columns = dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(themeManager.allAvailableThemes) { style in
                    Button {
                        themeManager.setTheme(style)
                    } label: {
                        themeCard(style: style)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("主题：\(style.displayName)")
                    .accessibilityAddTraits(themeManager.currentStyle.id == style.id ? .isSelected : [])
                }
            }
            Text("日间／黑夜跟随系统外观")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
        .padding(.vertical, 4)
        .listRowBackground(listRowBg)
    }

    private func themeCard(style: ThemeStyle) -> some View {
        let isSelected = themeManager.currentStyle.id == style.id
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    swatch(style.day)
                    swatch(style.night)
                }
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(palette.onAction, palette.actionFill)
                        .padding(4)
                }
            }
            Text(style.displayName)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? palette.textPrimary : palette.textSecondary)
                .lineLimit(1)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? palette.primary.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? palette.primary : palette.separator, lineWidth: isSelected ? 1.5 : 0.5)
        )
    }

    /// 一种外观的预览：底色 + 两束光晕 + 主操作色点
    private func swatch(_ tokens: ThemeTokens) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(uiColor: UIColor(rgb: tokens.background))
            LinearGradient(
                colors: [Color(uiColor: UIColor(rgb: tokens.glowA)), Color(uiColor: UIColor(rgb: tokens.glowB))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.9)
            Circle()
                .fill(Color(uiColor: UIColor(rgb: tokens.actionFill)))
                .frame(width: 12, height: 12)
                .padding(6)
        }
        .accessibilityHidden(true)
    }
}

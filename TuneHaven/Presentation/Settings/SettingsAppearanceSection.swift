import SwiftUI
import PhotosUI

struct SettingsAppearanceSection: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @EnvironmentObject private var snackbar: SnackbarState
    @Environment(\.themePalette) private var palette
    @Environment(\.settingsListRowBg) private var listRowBg

    @Binding var isExpanded: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                themeStyleRow
                wallpaperRow
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
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(ThemeRegistry.shared.allThemes) { style in
                    Button {
                        themeManager.setTheme(style)
                    } label: {
                        themeCard(style: style)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(listRowBg)
    }

    private func themeCard(style: ThemeStyle) -> some View {
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
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.3)))
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

    // MARK: - Wallpaper

    private var wallpaperRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("壁纸")
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            HStack(spacing: 12) {
                if let image = wallpaperManager.currentWallpaper {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(palette.primary, lineWidth: 2)
                            )

                        Button {
                            wallpaperManager.removeWallpaper()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, Color.red)
                        }
                        .offset(x: 6, y: -6)
                    }
                }

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundColor(palette.primary)
                        Text(wallpaperManager.currentWallpaper == nil ? "选择壁纸" : "更换壁纸")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    .frame(width: 80, height: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(palette.separator, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )
                }
                .buttonStyle(.borderless)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            wallpaperManager.setWallpaper(uiImage)
                            snackbar.show(message: "壁纸已应用")
                        }
                        selectedPhotoItem = nil
                    }
                }

                Spacer()
            }

            if wallpaperManager.currentWallpaper != nil {
                Text("壁纸将覆盖在主题背景之上，半透明效果让背景融入整体风格")
                    .font(.caption2)
                    .foregroundColor(palette.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(listRowBg)
    }
}

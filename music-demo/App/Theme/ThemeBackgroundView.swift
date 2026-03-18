import SwiftUI

struct ThemeBackgroundView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if wallpaperManager.useCustomWallpaper, let image = wallpaperManager.currentWallpaper {
                userWallpaperBackground(image)
            } else {
                themeBackground
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var themeBackground: some View {
        let config = themeManager.currentStyle.visualConfig
        switch config.backgroundType {
        case .solidColor:
            palette.background
        case .codeGenerated(let pattern):
            codeGeneratedBackground(pattern)
        case .userWallpaper:
            palette.background
        }
    }

    @ViewBuilder
    private func codeGeneratedBackground(_ pattern: ThemePatternType) -> some View {
        switch pattern {
        case .comicSky:
            ComicPopBackground()
                .environment(\.colorScheme, colorScheme)
        case .techGrid:
            CrimsonTechBackground()
                .environment(\.colorScheme, colorScheme)
        case .inkMountain:
            InkWashBackground()
                .environment(\.colorScheme, colorScheme)
        case .rosePetal:
            RoseDreamBackground()
                .environment(\.colorScheme, colorScheme)
        case .frostAurora:
            FrostEleganceBackground()
                .environment(\.colorScheme, colorScheme)
        }
    }

    private func userWallpaperBackground(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)

            palette.background.opacity(0.55)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        }
    }
}

// MARK: - 主题卡片修饰器

struct ThemedCardModifier: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        let config = themeManager.currentStyle.visualConfig
        switch config.cardStyle {
        case .standard:
            content
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        case .rounded:
            content
                .background(palette.surface.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(palette.primary.opacity(0.15), lineWidth: 1.5)
                )
        case .glassmorphism:
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.primary.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: palette.primary.opacity(0.08), radius: 8, y: 2)
        case .minimal:
            content
                .background(palette.surface.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .softFloat:
            content
                .background(palette.surface.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: palette.primary.opacity(0.1), radius: 12, y: 4)
        case .frosted:
            content
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    func themedCard() -> some View {
        modifier(ThemedCardModifier())
    }
}

// MARK: - 主题字体修饰器

struct ThemedFontModifier: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        let config = themeManager.currentStyle.visualConfig
        switch config.fontStyle {
        case .system:
            content.font(.system(size: size, weight: weight))
        case .rounded:
            content.font(.system(size: size, weight: weight, design: .rounded))
        case .monospaced:
            content.font(.system(size: size, weight: weight, design: .monospaced))
        case .serif:
            content.font(.system(size: size, weight: weight, design: .serif))
        }
    }
}

extension View {
    func themedFont(size: CGFloat = 16, weight: Font.Weight = .regular) -> some View {
        modifier(ThemedFontModifier(size: size, weight: weight))
    }
}

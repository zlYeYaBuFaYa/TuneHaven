import SwiftUI

// MARK: - 自适应背景环境键

private struct HasCustomBackgroundKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var hasCustomBackground: Bool {
        get { self[HasCustomBackgroundKey.self] }
        set { self[HasCustomBackgroundKey.self] = newValue }
    }
}

struct AdaptiveBackgroundModifier: ViewModifier {
    @Environment(\.hasCustomBackground) private var hasCustomBg
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content.background(hasCustomBg ? Color.clear : palette.background)
    }
}

extension View {
    func adaptiveBackground() -> some View {
        modifier(AdaptiveBackgroundModifier())
    }

    func themeContainerBackground() -> some View {
        modifier(ThemeContainerBackgroundModifier())
    }
}

struct ThemeContainerBackgroundModifier: ViewModifier {
    @Environment(\.hasCustomBackground) private var hasCustomBg
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content.background {
            if hasCustomBg {
                ThemeBackgroundView()
                    .ignoresSafeArea()
            } else {
                palette.background
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - 主题背景视图

struct ThemeBackgroundView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            palette.background

            if wallpaperManager.useCustomWallpaper, let image = wallpaperManager.currentWallpaper {
                userWallpaperBackground(image)
                    .transition(.opacity)
            } else {
                themeBackground
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: themeManager.currentStyle.id)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var themeBackground: some View {
        let config = themeManager.currentStyle.visualConfig
        switch config.backgroundType {
        case .solidColor:
            palette.background
        case .codeGenerated(let pattern):
            switch pattern {
            case .cosmicParticles:
                CosmicParticlesBackground()
            default:
                LinearGradient(
                    colors: [palette.gradientStart, palette.gradientEnd],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .userWallpaper:
            palette.background
        }
    }

    private func userWallpaperBackground(_ image: UIImage) -> some View {
        let overlayColor: Color = palette.background.opacity(0.55)
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()

            overlayColor

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
                        .stroke(palette.separator.opacity(0.3), lineWidth: 0.5)
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

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
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            palette.background
            themeBackground
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
            switch pattern {
            case .cosmicParticles:
                CosmicParticlesBackground()
            }
        case .userWallpaper:
            palette.background
        }
    }
}

// MARK: - 主题卡片修饰器

struct ThemedCardModifier: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        let visual = themeManager.currentStyle.visualConfig
        let card = visual.cardConfig
        let shape = RoundedRectangle(cornerRadius: card.cornerRadius)

        switch visual.cardStyle {
        case .standard:
            content
                .background(palette.surface.opacity(card.backgroundOpacity))
                .clipShape(shape)
        case .rounded:
            content
                .background(palette.surface.opacity(card.backgroundOpacity))
                .clipShape(shape)
                .overlay(shape.stroke(palette.primary.opacity(card.borderOpacity), lineWidth: card.borderWidth))
        case .glassmorphism:
            content
                .background(.ultraThinMaterial)
                .clipShape(shape)
                .overlay(shape.stroke(palette.primary.opacity(card.borderOpacity), lineWidth: card.borderWidth))
                .shadow(color: palette.primary.opacity(card.shadowOpacity), radius: card.shadowRadius, y: card.shadowY)
        case .minimal:
            content
                .background(palette.surface.opacity(card.backgroundOpacity))
                .clipShape(shape)
        case .softFloat:
            content
                .background(palette.surface.opacity(card.backgroundOpacity))
                .clipShape(shape)
                .shadow(color: palette.primary.opacity(card.shadowOpacity), radius: card.shadowRadius, y: card.shadowY)
        case .frosted:
            content
                .background(.thinMaterial)
                .clipShape(shape)
                .overlay(shape.stroke(palette.separator.opacity(card.borderOpacity), lineWidth: card.borderWidth))
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

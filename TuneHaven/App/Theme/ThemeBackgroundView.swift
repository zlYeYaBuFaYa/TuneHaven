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

/// 已有外层主题背景（Tab 根）时透明；否则（sheet、独立容器）自己画柔光，避免纯色底上的半透明卡片消失。
/// 不依赖 ThemeManager 环境对象，sheet 里也能安全使用
struct AdaptiveBackgroundModifier: ViewModifier {
    @Environment(\.hasCustomBackground) private var hasCustomBg
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if hasCustomBg {
                Color.clear
            } else if reduceTransparency {
                palette.background.ignoresSafeArea()
            } else {
                SoftGlowBackground(palette: palette)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func adaptiveBackground() -> some View {
        modifier(AdaptiveBackgroundModifier())
    }

    func themeContainerBackground() -> some View {
        modifier(ThemeContainerBackgroundModifier())
    }

    /// sheet 内容：sheet 会继承呈现方的 `hasCustomBackground = true`，但身后没有柔光，
    /// 这里复位让 `adaptiveBackground()` 自己绘制
    func sheetBackground() -> some View {
        environment(\.hasCustomBackground, false)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            palette.background
            themeBackground
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var themeBackground: some View {
        let config = themeManager.currentStyle.visualConfig
        switch config.backgroundType {
        case .solidColor, .userWallpaper:
            palette.background
        case .softGlow:
            // 减少透明度时只用不透明底色
            if reduceTransparency {
                palette.background
            } else {
                SoftGlowBackground(palette: palette)
            }
        }
    }
}

/// 三束低频柔光：左上、右侧、下部。静态绘制，不逐帧计算模糊（docs/UI设计文档.md §6.1）
struct SoftGlowBackground: View {
    let palette: ThemeColorPalette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = max(w, h)
            ZStack {
                palette.background
                RadialGradient(colors: [palette.glowA, palette.glowA.opacity(0)],
                               center: UnitPoint(x: 0.05, y: 0.12), startRadius: 0, endRadius: radius * 0.55)
                RadialGradient(colors: [palette.glowB, palette.glowB.opacity(0)],
                               center: UnitPoint(x: 1.0, y: 0.32), startRadius: 0, endRadius: radius * 0.5)
                RadialGradient(colors: [palette.glowC, palette.glowC.opacity(0)],
                               center: UnitPoint(x: 0.45, y: 1.0), startRadius: 0, endRadius: radius * 0.55)
            }
            .frame(width: w, height: h)
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

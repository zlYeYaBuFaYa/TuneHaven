import SwiftUI

struct RoseDreamBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                dreamGradient(size: geo.size)
                bokehLights(size: geo.size)
                fallingPetals(size: geo.size)
                softVignette(size: geo.size)
            }
        }
    }

    // MARK: - 梦幻粉色渐变

    private func dreamGradient(size: CGSize) -> some View {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(hex: "#1E0A14"),
                Color(hex: "#2A1220"),
                Color(hex: "#241828"),
                Color(hex: "#1A0E1E"),
            ]
            : [
                Color(hex: "#FFF0F3"),
                Color(hex: "#FFDBE5"),
                Color(hex: "#F8D0E0"),
                Color(hex: "#E8C8D8"),
                Color(hex: "#DCC8E0"),
            ]

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - 梦幻光斑 (Bokeh)

    private func bokehLights(size: CGSize) -> some View {
        let circles: [(x: CGFloat, y: CGFloat, r: CGFloat, opacity: Double)] = [
            (0.15, 0.10, 60,  0.12),
            (0.75, 0.08, 45,  0.10),
            (0.50, 0.25, 80,  0.08),
            (0.85, 0.35, 50,  0.10),
            (0.25, 0.45, 70,  0.07),
            (0.65, 0.55, 40,  0.09),
            (0.10, 0.65, 55,  0.06),
            (0.90, 0.70, 35,  0.08),
            (0.40, 0.80, 65,  0.05),
            (0.70, 0.15, 50,  0.11),
        ]
        let baseColor = colorScheme == .dark
            ? Color(hex: "#E0B5B5")
            : Color(hex: "#FFB6C1")

        return ZStack {
            ForEach(0..<circles.count, id: \.self) { i in
                let c = circles[i]
                let opacity = colorScheme == .dark ? c.opacity * 0.6 : c.opacity
                RadialGradient(
                    colors: [baseColor.opacity(opacity), baseColor.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: c.r
                )
                .frame(width: c.r * 2, height: c.r * 2)
                .position(x: size.width * c.x, y: size.height * c.y)
            }
        }
    }

    // MARK: - 飘落花瓣

    private func fallingPetals(size: CGSize) -> some View {
        let petals: [(x: CGFloat, y: CGFloat, size: CGFloat, rotation: Double, opacity: Double)] = [
            (0.12, 0.15, 14, 25,  0.35),
            (0.82, 0.10, 10, 60,  0.25),
            (0.35, 0.30, 16, 110, 0.30),
            (0.68, 0.22, 12, 170, 0.20),
            (0.20, 0.50, 11, 45,  0.25),
            (0.55, 0.42, 15, 85,  0.18),
            (0.90, 0.48, 9,  140, 0.22),
            (0.08, 0.72, 13, 200, 0.15),
            (0.45, 0.68, 17, 30,  0.20),
            (0.75, 0.65, 11, 95,  0.25),
            (0.30, 0.85, 10, 150, 0.12),
            (0.60, 0.80, 14, 70,  0.18),
            (0.15, 0.35, 8,  120, 0.20),
            (0.88, 0.58, 12, 55,  0.15),
        ]
        let petalColor = colorScheme == .dark
            ? Color(hex: "#D4A5A5")
            : Color(hex: "#F4A0B0")

        return ZStack {
            ForEach(0..<petals.count, id: \.self) { i in
                let p = petals[i]
                let opacity = colorScheme == .dark ? p.opacity * 0.5 : p.opacity
                petalShape(size: p.size)
                    .fill(petalColor.opacity(opacity))
                    .frame(width: p.size * 2, height: p.size * 1.4)
                    .rotationEffect(.degrees(p.rotation))
                    .position(x: size.width * p.x, y: size.height * p.y)
            }
        }
    }

    private func petalShape(size: CGFloat) -> Path {
        var path = Path()
        let w = size * 2
        let h = size * 1.4
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control: CGPoint(x: w * 1.1, y: h * 0.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control: CGPoint(x: -w * 0.1, y: h * 0.5)
        )
        path.closeSubpath()
        return path
    }

    // MARK: - 柔和暗角

    private func softVignette(size: CGSize) -> some View {
        let opacity = colorScheme == .dark ? 0.3 : 0.08
        return RadialGradient(
            colors: [.clear, Color.black.opacity(opacity)],
            center: .center,
            startRadius: min(size.width, size.height) * 0.3,
            endRadius: max(size.width, size.height) * 0.7
        )
    }
}

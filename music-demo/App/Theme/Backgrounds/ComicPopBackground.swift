import SwiftUI

struct ComicPopBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                gradientSky(size: geo.size)
                halftonePattern(size: geo.size)
                cloudLayer(size: geo.size)
                sparkles(size: geo.size)
            }
        }
    }

    // MARK: - 渐变天空 (日漫夕阳风)

    private func gradientSky(size: CGSize) -> some View {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(hex: "#1A0E20"),
                Color(hex: "#2A1535"),
                Color(hex: "#3D1A3A"),
                Color(hex: "#1A0E20")
            ]
            : [
                Color(hex: "#FFE4CC"),
                Color(hex: "#FCCFB5"),
                Color(hex: "#F4B8C1"),
                Color(hex: "#D4C5E2"),
                Color(hex: "#B8D4E8")
            ]

        return LinearGradient(
            colors: colors,
            startPoint: .bottom,
            endPoint: .top
        )
    }

    // MARK: - 半调网点 (漫画特色)

    private func halftonePattern(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let dotSpacing: CGFloat = 24
            let dotRadius: CGFloat = colorScheme == .dark ? 1.2 : 1.5
            let opacity: CGFloat = colorScheme == .dark ? 0.15 : 0.08

            for x in stride(from: 0, to: canvasSize.width, by: dotSpacing) {
                for y in stride(from: 0, to: canvasSize.height, by: dotSpacing) {
                    let offsetX = Int(y / dotSpacing) % 2 == 0 ? dotSpacing / 2 : 0
                    let point = CGPoint(x: x + offsetX, y: y)
                    let path = Circle().path(in: CGRect(
                        x: point.x - dotRadius,
                        y: point.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    ))
                    context.fill(path, with: .color(.white.opacity(opacity)))
                }
            }
        }
    }

    // MARK: - 云朵层

    private func cloudLayer(size: CGSize) -> some View {
        let opacity = colorScheme == .dark ? 0.08 : 0.25

        return ZStack {
            singleCloud(width: size.width * 0.45, height: 35)
                .fill(Color.white.opacity(opacity))
                .offset(x: -size.width * 0.15, y: size.height * 0.15)

            singleCloud(width: size.width * 0.55, height: 40)
                .fill(Color.white.opacity(opacity * 0.8))
                .offset(x: size.width * 0.2, y: size.height * 0.08)

            singleCloud(width: size.width * 0.35, height: 28)
                .fill(Color.white.opacity(opacity * 0.6))
                .offset(x: size.width * 0.05, y: size.height * 0.25)

            singleCloud(width: size.width * 0.4, height: 30)
                .fill(Color.white.opacity(opacity * 0.5))
                .offset(x: -size.width * 0.25, y: size.height * 0.35)
        }
    }

    private func singleCloud(width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        let w = width
        let h = height
        path.addEllipse(in: CGRect(x: 0, y: h * 0.3, width: w * 0.35, height: h * 0.7))
        path.addEllipse(in: CGRect(x: w * 0.15, y: 0, width: w * 0.4, height: h))
        path.addEllipse(in: CGRect(x: w * 0.35, y: h * 0.15, width: w * 0.4, height: h * 0.85))
        path.addEllipse(in: CGRect(x: w * 0.6, y: h * 0.35, width: w * 0.4, height: h * 0.65))
        return path
    }

    // MARK: - 星星/闪光 装饰

    private func sparkles(size: CGSize) -> some View {
        let opacity = colorScheme == .dark ? 0.5 : 0.25
        let positions: [(CGFloat, CGFloat, CGFloat)] = [
            (0.15, 0.12, 4),
            (0.72, 0.08, 5),
            (0.85, 0.22, 3.5),
            (0.35, 0.05, 3),
            (0.55, 0.18, 4.5),
            (0.1,  0.3,  3),
            (0.9,  0.35, 3.5),
        ]

        return ZStack {
            ForEach(0..<positions.count, id: \.self) { i in
                let (px, py, sz) = positions[i]
                fourPointStar(size: sz)
                    .fill(Color.white.opacity(opacity))
                    .frame(width: sz * 3, height: sz * 3)
                    .position(x: size.width * px, y: size.height * py)
            }
        }
    }

    private func fourPointStar(size: CGFloat) -> Path {
        var path = Path()
        let center = CGPoint(x: size * 1.5, y: size * 1.5)
        let outer = size * 1.5
        let inner = size * 0.4
        let points = 4
        for i in 0..<(points * 2) {
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            let r = i % 2 == 0 ? outer : inner
            let x = center.x + CGFloat(cos(angle)) * r
            let y = center.y + CGFloat(sin(angle)) * r
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

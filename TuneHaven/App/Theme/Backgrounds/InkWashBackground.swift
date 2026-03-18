import SwiftUI

struct InkWashBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                paperBase(size: geo.size)
                inkMountains(size: geo.size)
                brushStrokes(size: geo.size)
                paperTexture(size: geo.size)
            }
        }
    }

    // MARK: - 宣纸底色

    private func paperBase(size: CGSize) -> some View {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(hex: "#121210"),
                Color(hex: "#161614"),
                Color(hex: "#1A1A17"),
            ]
            : [
                Color(hex: "#F5F0E8"),
                Color(hex: "#F0EBE2"),
                Color(hex: "#EBE6DC"),
            ]

        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - 水墨远山

    private func inkMountains(size: CGSize) -> some View {
        ZStack {
            mountainLayer(
                size: size,
                yOffset: 0.55,
                height: 0.25,
                opacity: colorScheme == .dark ? 0.08 : 0.06,
                peaks: [0.0, 0.12, 0.25, 0.15, 0.35, 0.22, 0.18, 0.3, 0.1, 0.2, 0.0]
            )

            mountainLayer(
                size: size,
                yOffset: 0.65,
                height: 0.2,
                opacity: colorScheme == .dark ? 0.12 : 0.08,
                peaks: [0.0, 0.08, 0.2, 0.12, 0.28, 0.15, 0.22, 0.1, 0.15, 0.05, 0.0]
            )

            mountainLayer(
                size: size,
                yOffset: 0.75,
                height: 0.15,
                opacity: colorScheme == .dark ? 0.18 : 0.1,
                peaks: [0.0, 0.05, 0.15, 0.08, 0.2, 0.1, 0.12, 0.06, 0.1, 0.03, 0.0]
            )
        }
    }

    private func mountainLayer(
        size: CGSize,
        yOffset: CGFloat,
        height: CGFloat,
        opacity: CGFloat,
        peaks: [CGFloat]
    ) -> some View {
        let inkColor = colorScheme == .dark
            ? Color.white.opacity(opacity)
            : Color(hex: "#3A3A3A").opacity(opacity)

        return Canvas { context, canvasSize in
            var path = Path()
            let baseY = canvasSize.height * yOffset
            let segmentWidth = canvasSize.width / CGFloat(peaks.count - 1)

            path.move(to: CGPoint(x: 0, y: canvasSize.height))
            path.addLine(to: CGPoint(x: 0, y: baseY))

            for i in 0..<peaks.count {
                let x = CGFloat(i) * segmentWidth
                let y = baseY - canvasSize.height * height * peaks[i]
                if i == 0 {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let prevX = CGFloat(i - 1) * segmentWidth
                    let midX = (prevX + x) / 2
                    let prevY = baseY - canvasSize.height * height * peaks[i - 1]
                    path.addQuadCurve(
                        to: CGPoint(x: x, y: y),
                        control: CGPoint(x: midX, y: min(prevY, y) - canvasSize.height * 0.01)
                    )
                }
            }

            path.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height))
            path.closeSubpath()

            context.fill(path, with: .color(inkColor))
        }
    }

    // MARK: - 墨迹飞白

    private func brushStrokes(size: CGSize) -> some View {
        let strokeColor = colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color(hex: "#3A3A3A").opacity(0.025)

        return Canvas { context, canvasSize in
            let strokes: [(start: CGPoint, end: CGPoint, width: CGFloat)] = [
                (
                    CGPoint(x: canvasSize.width * 0.05, y: canvasSize.height * 0.2),
                    CGPoint(x: canvasSize.width * 0.35, y: canvasSize.height * 0.18),
                    3
                ),
                (
                    CGPoint(x: canvasSize.width * 0.6, y: canvasSize.height * 0.1),
                    CGPoint(x: canvasSize.width * 0.9, y: canvasSize.height * 0.12),
                    2
                ),
                (
                    CGPoint(x: canvasSize.width * 0.15, y: canvasSize.height * 0.4),
                    CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.38),
                    2.5
                ),
            ]

            for stroke in strokes {
                var path = Path()
                path.move(to: stroke.start)
                let midX = (stroke.start.x + stroke.end.x) / 2
                let midY = (stroke.start.y + stroke.end.y) / 2 - 8
                path.addQuadCurve(to: stroke.end, control: CGPoint(x: midX, y: midY))
                context.stroke(path, with: .color(strokeColor), lineWidth: stroke.width)
            }
        }
    }

    // MARK: - 纸纹理 (细微噪点效果)

    private func paperTexture(size: CGSize) -> some View {
        let opacity = colorScheme == .dark ? 0.02 : 0.03
        return Canvas { context, canvasSize in
            let step: CGFloat = 6
            for x in stride(from: 0, to: canvasSize.width, by: step) {
                for y in stride(from: 0, to: canvasSize.height, by: step) {
                    let hash = (Int(x) * 7 + Int(y) * 13) % 100
                    if hash < 15 {
                        let grain = Circle().path(in: CGRect(x: x, y: y, width: 1, height: 1))
                        let grainOpacity = Double(hash) / 100.0 * opacity
                        let color = colorScheme == .dark ? Color.white : Color.black
                        context.fill(grain, with: .color(color.opacity(grainOpacity)))
                    }
                }
            }
        }
    }
}

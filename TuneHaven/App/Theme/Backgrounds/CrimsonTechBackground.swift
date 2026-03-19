import SwiftUI

struct CrimsonTechBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                darkBase(size: geo.size)
                gridLines(size: geo.size)
                circuitTraces(size: geo.size)
                glowSpots(size: geo.size)
                hexOverlay(size: geo.size)
            }
        }
        .drawingGroup()
    }

    // MARK: - 深色基底（带微妙渐变）

    private func darkBase(size: CGSize) -> some View {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(hex: "#0A0A0F"),
                Color(hex: "#0E0A15"),
                Color(hex: "#12080B"),
                Color(hex: "#0A0A0F")
            ]
            : [
                Color(hex: "#F0EAEE"),
                Color(hex: "#EAE4EC"),
                Color(hex: "#ECE6EA"),
                Color(hex: "#F0EAEE")
            ]

        return RadialGradient(
            colors: colors,
            center: .center,
            startRadius: 0,
            endRadius: max(size.width, size.height) * 0.8
        )
    }

    // MARK: - 网格线

    private func gridLines(size: CGSize) -> some View {
        let lineColor = colorScheme == .dark
            ? Color(hex: "#FF5252").opacity(0.06)
            : Color(hex: "#D32F2F").opacity(0.04)
        let spacing: CGFloat = 50

        return Canvas { context, canvasSize in
            for x in stride(from: 0, to: canvasSize.width, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
            for y in stride(from: 0, to: canvasSize.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        }
        .drawingGroup()
    }

    // MARK: - 电路走线

    private func circuitTraces(size: CGSize) -> some View {
        let traceColor = colorScheme == .dark
            ? Color(hex: "#FF5252").opacity(0.12)
            : Color(hex: "#D32F2F").opacity(0.06)

        return Canvas { context, canvasSize in
            let traces: [(start: CGPoint, segments: [(dx: CGFloat, dy: CGFloat)])] = [
                (
                    start: CGPoint(x: 0, y: canvasSize.height * 0.3),
                    segments: [(120, 0), (0, -60), (80, 0), (0, 40), (100, 0)]
                ),
                (
                    start: CGPoint(x: canvasSize.width, y: canvasSize.height * 0.6),
                    segments: [(-150, 0), (0, 80), (-90, 0), (0, -50), (-70, 0)]
                ),
                (
                    start: CGPoint(x: canvasSize.width * 0.4, y: 0),
                    segments: [(0, 100), (60, 0), (0, 70), (-40, 0), (0, 50)]
                ),
                (
                    start: CGPoint(x: canvasSize.width * 0.7, y: canvasSize.height),
                    segments: [(0, -90), (-50, 0), (0, -60), (70, 0), (0, -40)]
                ),
            ]

            for trace in traces {
                var path = Path()
                path.move(to: trace.start)
                var current = trace.start
                for seg in trace.segments {
                    current = CGPoint(x: current.x + seg.dx, y: current.y + seg.dy)
                    path.addLine(to: current)
                }
                context.stroke(path, with: .color(traceColor), lineWidth: 1.5)

                let nodeSize: CGFloat = 4
                let nodePath = Circle().path(in: CGRect(
                    x: current.x - nodeSize / 2,
                    y: current.y - nodeSize / 2,
                    width: nodeSize,
                    height: nodeSize
                ))
                context.fill(nodePath, with: .color(traceColor))
            }
        }
        .drawingGroup()
    }

    // MARK: - 霓虹光点

    private func glowSpots(size: CGSize) -> some View {
        let positions: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
            (0.2, 0.25, 80),
            (0.75, 0.15, 60),
            (0.5, 0.65, 100),
            (0.85, 0.55, 70),
            (0.15, 0.8, 55),
        ]
        let glowColor = colorScheme == .dark
            ? Color(hex: "#FF5252")
            : Color(hex: "#D32F2F")

        return ZStack {
            ForEach(0..<positions.count, id: \.self) { i in
                let pos = positions[i]
                let opacity = colorScheme == .dark ? 0.08 : 0.04
                RadialGradient(
                    colors: [glowColor.opacity(opacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: pos.r
                )
                .frame(width: pos.r * 2, height: pos.r * 2)
                .position(x: size.width * pos.x, y: size.height * pos.y)
            }
        }
    }

    // MARK: - 六边形装饰

    private func hexOverlay(size: CGSize) -> some View {
        let hexColor = colorScheme == .dark
            ? Color(hex: "#FF5252").opacity(0.04)
            : Color(hex: "#D32F2F").opacity(0.025)

        return Canvas { context, canvasSize in
            let hexRadius: CGFloat = 35
            let hexPositions: [(CGFloat, CGFloat)] = [
                (0.12, 0.15), (0.88, 0.12),
                (0.5, 0.45),
                (0.2, 0.7), (0.78, 0.75),
                (0.4, 0.85),
            ]
            for (px, py) in hexPositions {
                let center = CGPoint(x: canvasSize.width * px, y: canvasSize.height * py)
                let path = hexagonPath(center: center, radius: hexRadius)
                context.stroke(path, with: .color(hexColor), lineWidth: 1)
            }
        }
        .drawingGroup()
    }

    private func hexagonPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for i in 0..<6 {
            let angle = Double(i) * .pi / 3 - .pi / 6
            let x = center.x + CGFloat(cos(angle)) * radius
            let y = center.y + CGFloat(sin(angle)) * radius
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

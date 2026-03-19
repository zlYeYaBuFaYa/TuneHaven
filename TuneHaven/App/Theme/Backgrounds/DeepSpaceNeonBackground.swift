import SwiftUI

struct DeepSpaceNeonBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                spaceBase(size: geo.size)
                hexGrid(size: geo.size)
                circuitTraces(size: geo.size)
                neonGlowSpots(size: geo.size)
                scanLine(size: geo.size)
            }
        }
        .drawingGroup()
    }

    // MARK: - 深空渐变基底

    private func spaceBase(size: CGSize) -> some View {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(hex: "#050810"),
                Color(hex: "#080C18"),
                Color(hex: "#0A1020"),
                Color(hex: "#0F1629")
            ]
            : [
                Color(hex: "#EDF6FF"),
                Color(hex: "#E0F2FE"),
                Color(hex: "#F0F9FF"),
                Color(hex: "#E0F2FE")
            ]

        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - 六边形网格

    private func hexGrid(size: CGSize) -> some View {
        let lineColor = colorScheme == .dark
            ? Color(hex: "#00D4FF").opacity(0.04)
            : Color(hex: "#0891B2").opacity(0.06)
        let hexRadius: CGFloat = 40
        let horizontalSpacing = hexRadius * 1.75
        let verticalSpacing = hexRadius * 1.52

        return Canvas { context, canvasSize in
            let cols = Int(canvasSize.width / horizontalSpacing) + 2
            let rows = Int(canvasSize.height / verticalSpacing) + 2

            for row in 0..<rows {
                for col in 0..<cols {
                    let offsetX: CGFloat = row.isMultiple(of: 2) ? 0 : horizontalSpacing / 2
                    let cx = CGFloat(col) * horizontalSpacing + offsetX
                    let cy = CGFloat(row) * verticalSpacing
                    let path = hexagonPath(center: CGPoint(x: cx, y: cy), radius: hexRadius)
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                }
            }
        }
        .drawingGroup()
    }

    // MARK: - 电路走线

    private func circuitTraces(size: CGSize) -> some View {
        let traceColor = colorScheme == .dark
            ? Color(hex: "#00D4FF").opacity(0.10)
            : Color(hex: "#0891B2").opacity(0.05)
        let nodeColor = colorScheme == .dark
            ? Color(hex: "#00D4FF").opacity(0.20)
            : Color(hex: "#0891B2").opacity(0.10)

        return Canvas { context, canvasSize in
            let traces: [(start: CGPoint, segments: [(dx: CGFloat, dy: CGFloat)])] = [
                (
                    start: CGPoint(x: 0, y: canvasSize.height * 0.2),
                    segments: [(100, 0), (0, -40), (60, 0), (0, 60), (80, 0), (0, -30)]
                ),
                (
                    start: CGPoint(x: canvasSize.width, y: canvasSize.height * 0.5),
                    segments: [(-130, 0), (0, 70), (-80, 0), (0, -40), (-60, 0)]
                ),
                (
                    start: CGPoint(x: canvasSize.width * 0.3, y: canvasSize.height),
                    segments: [(0, -80), (50, 0), (0, -60), (-30, 0), (0, -50), (70, 0)]
                ),
                (
                    start: CGPoint(x: canvasSize.width * 0.8, y: 0),
                    segments: [(0, 70), (-60, 0), (0, 50), (40, 0), (0, 80)]
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
                context.stroke(path, with: .color(traceColor), lineWidth: 1)

                let nodeSize: CGFloat = 5
                let nodePath = Circle().path(in: CGRect(
                    x: current.x - nodeSize / 2,
                    y: current.y - nodeSize / 2,
                    width: nodeSize,
                    height: nodeSize
                ))
                context.fill(nodePath, with: .color(nodeColor))
            }
        }
        .drawingGroup()
    }

    // MARK: - 霓虹光晕

    private func neonGlowSpots(size: CGSize) -> some View {
        let spots: [(x: CGFloat, y: CGFloat, r: CGFloat, isCyan: Bool)] = [
            (0.15, 0.20, 90,  true),
            (0.80, 0.12, 70,  true),
            (0.50, 0.55, 110, true),
            (0.25, 0.75, 65,  false),
            (0.85, 0.60, 80,  false),
            (0.60, 0.85, 60,  true),
        ]
        let cyanColor = colorScheme == .dark
            ? Color(hex: "#00D4FF") : Color(hex: "#0891B2")
        let purpleColor = colorScheme == .dark
            ? Color(hex: "#7C3AED") : Color(hex: "#8B5CF6")

        return ZStack {
            ForEach(0..<spots.count, id: \.self) { i in
                let spot = spots[i]
                let color = spot.isCyan ? cyanColor : purpleColor
                let opacity = colorScheme == .dark ? 0.07 : 0.04
                RadialGradient(
                    colors: [color.opacity(opacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: spot.r
                )
                .frame(width: spot.r * 2, height: spot.r * 2)
                .position(x: size.width * spot.x, y: size.height * spot.y)
            }
        }
    }

    // MARK: - 扫描线效果

    private func scanLine(size: CGSize) -> some View {
        let lineColor = colorScheme == .dark
            ? Color(hex: "#00D4FF").opacity(0.02)
            : Color(hex: "#0891B2").opacity(0.015)
        let spacing: CGFloat = 4

        return Canvas { context, canvasSize in
            for y in stride(from: 0, to: canvasSize.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        }
        .drawingGroup()
    }

    // MARK: - 六边形路径

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

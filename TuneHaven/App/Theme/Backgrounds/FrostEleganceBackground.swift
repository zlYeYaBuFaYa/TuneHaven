import SwiftUI

struct FrostEleganceBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                frostGradient(size: geo.size)
                auroraBands(size: geo.size)
                iceShards(size: geo.size)
                frostCrystals(size: geo.size)
                frostedEdge(size: geo.size)
            }
        }
    }

    // MARK: - 冰霜渐变底色

    private func frostGradient(size: CGSize) -> some View {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(hex: "#0A1218"),
                Color(hex: "#0E1A22"),
                Color(hex: "#101820"),
                Color(hex: "#0C141C"),
            ]
            : [
                Color(hex: "#EDF4F8"),
                Color(hex: "#E0EEF3"),
                Color(hex: "#D5E8F0"),
                Color(hex: "#CDE0EA"),
            ]

        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - 极光光带

    private func auroraBands(size: CGSize) -> some View {
        let bands: [(yFrac: CGFloat, height: CGFloat, colors: [Color], opacity: Double)] = buildAuroraBands()

        return ZStack {
            ForEach(0..<bands.count, id: \.self) { i in
                let band = bands[i]
                LinearGradient(
                    colors: band.colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: band.height)
                .rotationEffect(.degrees(-3 + Double(i) * 2))
                .offset(y: size.height * band.yFrac - size.height / 2)
                .opacity(band.opacity)
            }
        }
    }

    private func buildAuroraBands() -> [(yFrac: CGFloat, height: CGFloat, colors: [Color], opacity: Double)] {
        if colorScheme == .dark {
            let c1: [Color] = [Color(hex: "#4AEADC").opacity(0.12), Color(hex: "#8BA5A0").opacity(0.05), .clear]
            let c2: [Color] = [.clear, Color(hex: "#A0BDB8").opacity(0.08), Color(hex: "#6CC4B0").opacity(0.10), .clear]
            let c3: [Color] = [Color(hex: "#4AEADC").opacity(0.06), .clear, Color(hex: "#8BA5A0").opacity(0.08)]
            return [(0.15, 120, c1, 1.0), (0.30, 90, c2, 1.0), (0.50, 100, c3, 1.0)]
        } else {
            let c1: [Color] = [Color(hex: "#8BA5A0").opacity(0.08), Color(hex: "#A0C4BC").opacity(0.05), .clear]
            let c2: [Color] = [.clear, Color(hex: "#9BB8B0").opacity(0.06), .clear]
            let c3: [Color] = [Color(hex: "#8BA5A0").opacity(0.04), .clear, Color(hex: "#B0D0C8").opacity(0.06)]
            return [(0.12, 100, c1, 1.0), (0.28, 80, c2, 1.0), (0.48, 90, c3, 1.0)]
        }
    }

    // MARK: - 冰棱

    private func iceShards(size: CGSize) -> some View {
        let shardColor = colorScheme == .dark
            ? Color(hex: "#A0BDB8").opacity(0.06)
            : Color(hex: "#8BA5A0").opacity(0.04)

        return Canvas { context, canvasSize in
            let shards: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: Double)] = [
                (0.05, 0.0,  2, 120, 15),
                (0.15, 0.0,  1.5, 80, 8),
                (0.25, 0.0,  2, 100, -5),
                (0.72, 0.0,  1.5, 90, 12),
                (0.85, 0.0,  2, 110, -8),
                (0.95, 0.0,  1.5, 70, 3),
                (0.10, 1.0,  2, 95, 175),
                (0.40, 1.0,  1.5, 75, 168),
                (0.60, 1.0,  2, 105, -172),
                (0.88, 1.0,  1.5, 85, 178),
            ]

            for shard in shards {
                let startX: CGFloat = canvasSize.width * shard.x
                let startY: CGFloat = shard.y == 0 ? 0 : canvasSize.height
                let rad: Double = shard.angle * .pi / 180
                let direction: CGFloat = shard.y < 0.5 ? 1 : -1
                let tipX: CGFloat = startX + CGFloat(Foundation.sin(rad)) * shard.h
                let tipY: CGFloat = startY + direction * shard.h * CGFloat(Foundation.cos(rad))

                var path = Path()
                path.move(to: CGPoint(x: startX - shard.w, y: startY))
                path.addLine(to: CGPoint(x: tipX, y: tipY))
                path.addLine(to: CGPoint(x: startX + shard.w, y: startY))
                path.closeSubpath()

                context.fill(path, with: .color(shardColor))
            }
        }
    }

    // MARK: - 霜花结晶

    private func frostCrystals(size: CGSize) -> some View {
        let crystalColor = colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(hex: "#8BA5A0").opacity(0.06)

        let positions: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
            (0.10, 0.20, 20),
            (0.30, 0.12, 15),
            (0.55, 0.30, 22),
            (0.80, 0.18, 18),
            (0.20, 0.55, 16),
            (0.65, 0.50, 20),
            (0.90, 0.45, 14),
            (0.15, 0.78, 18),
            (0.45, 0.70, 22),
            (0.75, 0.72, 16),
            (0.35, 0.90, 14),
            (0.85, 0.85, 20),
        ]

        return Canvas { context, canvasSize in
            for pos in positions {
                let center = CGPoint(x: canvasSize.width * pos.x, y: canvasSize.height * pos.y)
                let r: CGFloat = pos.r
                for branch in 0..<6 {
                    let angle: Double = Double(branch) * .pi / 3
                    let cosA = CGFloat(Foundation.cos(angle))
                    let sinA = CGFloat(Foundation.sin(angle))

                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + cosA * r, y: center.y + sinA * r))

                    let midR: CGFloat = r * 0.5
                    let midPoint = CGPoint(x: center.x + cosA * midR, y: center.y + sinA * midR)

                    let a1: Double = angle + .pi / 6
                    let a2: Double = angle - .pi / 6
                    let subLen: CGFloat = r * 0.3

                    var b1 = Path()
                    b1.move(to: midPoint)
                    b1.addLine(to: CGPoint(
                        x: midPoint.x + CGFloat(Foundation.cos(a1)) * subLen,
                        y: midPoint.y + CGFloat(Foundation.sin(a1)) * subLen
                    ))
                    var b2 = Path()
                    b2.move(to: midPoint)
                    b2.addLine(to: CGPoint(
                        x: midPoint.x + CGFloat(Foundation.cos(a2)) * subLen,
                        y: midPoint.y + CGFloat(Foundation.sin(a2)) * subLen
                    ))

                    context.stroke(path, with: .color(crystalColor), lineWidth: 0.8)
                    context.stroke(b1, with: .color(crystalColor), lineWidth: 0.5)
                    context.stroke(b2, with: .color(crystalColor), lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: - 边缘霜雾

    private func frostedEdge(size: CGSize) -> some View {
        let edgeColor = colorScheme == .dark
            ? Color(hex: "#A0BDB8").opacity(0.06)
            : Color.white.opacity(0.3)

        return ZStack {
            LinearGradient(
                colors: [edgeColor, .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.12)
            )
            LinearGradient(
                colors: [edgeColor, .clear],
                startPoint: .bottom,
                endPoint: UnitPoint(x: 0.5, y: 0.88)
            )
            LinearGradient(
                colors: [edgeColor.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.08, y: 0.5)
            )
            LinearGradient(
                colors: [edgeColor.opacity(0.5), .clear],
                startPoint: .trailing,
                endPoint: UnitPoint(x: 0.92, y: 0.5)
            )
        }
    }
}

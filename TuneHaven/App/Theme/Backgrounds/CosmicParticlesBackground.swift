import SwiftUI

struct CosmicParticlesBackground: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    @State private var particles: [Particle] = Particle.generate(count: 40)
    @State private var startDate: Date = .now
    @State private var isAnimating: Bool = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { timeline in
            let elapsed = isAnimating ? timeline.date.timeIntervalSince(startDate) : 0
            let colors = [palette.gradientStart, palette.gradientEnd, palette.primary]
            Canvas { context, size in
                for particle in particles {
                    let currentY = particle.initialY - particle.speed * elapsed
                    let wrappedY = currentY.truncatingRemainder(dividingBy: 1.1)
                    let y = wrappedY < -0.05 ? wrappedY + 1.1 : wrappedY
                    let drift = sin(elapsed * particle.driftFreq + particle.driftPhase) * 0.015
                    let x = particle.initialX + drift

                    let rect = CGRect(
                        x: x * size.width - particle.size / 2,
                        y: y * size.height - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )
                    context.opacity = particle.opacity
                    context.fill(Circle().path(in: rect), with: .color(colors[particle.colorIndex % colors.count]))
                }
            }
        }
        .background(
            LinearGradient(
                colors: [palette.background, palette.surfaceSecondary],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                startDate = .now
                isAnimating = true
            case .background, .inactive:
                isAnimating = false
            @unknown default:
                break
            }
        }
    }
}

private struct Particle {
    let initialX: Double
    let initialY: Double
    let size: Double
    let opacity: Double
    let speed: Double
    let driftFreq: Double
    let driftPhase: Double
    let colorIndex: Int

    static func generate(count: Int) -> [Particle] {
        (0..<count).map { _ in
            Particle(
                initialX: Double.random(in: 0...1),
                initialY: Double.random(in: 0...1),
                size: Double.random(in: 1.5...4),
                opacity: Double.random(in: 0.15...0.6),
                speed: Double.random(in: 0.003...0.015),
                driftFreq: Double.random(in: 0.3...1.2),
                driftPhase: Double.random(in: 0...(.pi * 2)),
                colorIndex: Int.random(in: 0...2)
            )
        }
    }
}

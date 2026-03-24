import SwiftUI

struct CosmicParticlesBackground: View {
    @Environment(\.themePalette) private var palette

    @State private var particles: [Particle] = []
    @State private var startDate: Date = .now

    private let particleCount = 40

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
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
                    context.fill(Circle().path(in: rect), with: .color(particle.color))
                }
            }
            .drawingGroup()
        }
        .background(
            LinearGradient(
                colors: [palette.background, palette.surfaceSecondary],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear { setupParticles() }
    }

    private func setupParticles() {
        guard particles.isEmpty else { return }
        startDate = .now
        particles = (0..<particleCount).map { _ in
            Particle(
                initialX: Double.random(in: 0...1),
                initialY: Double.random(in: 0...1),
                size: Double.random(in: 1.5...4),
                opacity: Double.random(in: 0.15...0.6),
                speed: Double.random(in: 0.003...0.015),
                driftFreq: Double.random(in: 0.3...1.2),
                driftPhase: Double.random(in: 0...(.pi * 2)),
                color: [palette.gradientStart, palette.gradientEnd, palette.primary].randomElement() ?? palette.primary
            )
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
    let color: Color
}

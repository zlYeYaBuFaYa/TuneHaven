import SwiftUI

struct CosmicParticlesBackground: View {
    @Environment(\.themePalette) private var palette

    @State private var particles: [Particle] = []
    @State private var lastUpdate: Date?

    private let particleCount = 40

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.x * size.width - particle.size / 2,
                        y: particle.y * size.height - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )
                    context.opacity = particle.opacity
                    context.fill(Circle().path(in: rect), with: .color(particle.color))
                }
            }
            .onChange(of: timeline.date) { _, _ in
                updateParticles()
            }
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
        particles = (0..<particleCount).map { _ in
            Particle(
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: Double.random(in: 1.5...4),
                opacity: Double.random(in: 0.15...0.6),
                speed: Double.random(in: 0.0002...0.001),
                color: [palette.gradientStart, palette.gradientEnd, palette.primary].randomElement() ?? palette.primary
            )
        }
    }

    private func updateParticles() {
        for i in particles.indices {
            particles[i].y -= particles[i].speed
            particles[i].x += Double.random(in: -0.0003...0.0003)
            if particles[i].y < -0.05 {
                particles[i].y = 1.05
                particles[i].x = Double.random(in: 0...1)
            }
        }
    }
}

private struct Particle {
    var x: Double
    var y: Double
    var size: Double
    var opacity: Double
    var speed: Double
    var color: Color
}

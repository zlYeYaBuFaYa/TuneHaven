import SwiftUI

struct CosmicParticlesBackground: View {
    @Environment(\.themePalette) private var palette

    @State private var particles: [Particle] = []
    @State private var timer: Timer?

    private let particleCount = 40

    var body: some View {
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
        .background(
            LinearGradient(
                colors: [palette.background, palette.surfaceSecondary],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear { setupParticles() }
        .onDisappear { stopTimer() }
    }

    private func setupParticles() {
        guard timer == nil else { return }

        particles = (0..<particleCount).map { _ in
            Particle(
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: Double.random(in: 1.5...4),
                opacity: Double.random(in: 0.15...0.6),
                speed: Double.random(in: 0.0002...0.001),
                color: [palette.gradientStart, palette.gradientEnd, palette.primary].randomElement()!
            )
        }

        let newTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
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
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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

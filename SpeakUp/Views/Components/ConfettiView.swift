import SwiftUI

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animate = false

    private let colors: [Color] = [.teal, .orange, .purple, .yellow, .green, .pink, .blue]

    var body: some View {
        Canvas { context, size in
            for particle in particles {
                let rect = CGRect(
                    x: particle.x * size.width - 4,
                    y: animate ? particle.endY * size.height : particle.startY * size.height,
                    width: 8,
                    height: 8
                )
                let path = Path(ellipseIn: rect)
                context.fill(path, with: .color(particle.color.opacity(animate ? 0 : 1)))
            }
        }
        .onAppear {
            particles = (0..<40).map { _ in
                ConfettiParticle(
                    x: CGFloat.random(in: 0...1),
                    startY: CGFloat.random(in: -0.3...0),
                    endY: CGFloat.random(in: 0.8...1.2),
                    color: colors.randomElement()!
                )
            }
            withAnimation(.easeOut(duration: 2.0)) {
                animate = true
            }
        }
    }
}

private struct ConfettiParticle {
    let x: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let color: Color
}

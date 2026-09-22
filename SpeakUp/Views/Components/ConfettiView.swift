import SwiftUI

/// A one-shot burst of paper confetti.
///
/// The old version animated a `Canvas` with `withAnimation`, which a `Canvas`
/// cannot interpolate - every particle jumped straight to its faded end state,
/// so none of the five screens that "celebrate" ever showed a single piece.
///
/// Each particle's position is now a closed-form function of time (gravity
/// plus linear air drag), so the `TimelineView` only asks where everything is
/// at `t`: no per-frame state, no drift. The timeline is torn down once the
/// last piece has faded, and Reduce Motion renders nothing at all.
struct ConfettiView: View {
    /// Where the burst leaves from, in unit coordinates of this view.
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.3)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var particles = ConfettiParticle.burst(count: 76)
    @State private var finished = false

    var body: some View {
        if !reduceMotion, !finished {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSince(start)
                    let from = CGPoint(x: origin.x * size.width, y: origin.y * size.height)
                    for particle in particles {
                        particle.draw(in: context, from: from, at: t)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(ConfettiParticle.lifetime))
                finished = true
            }
        }
    }
}

// MARK: - Particle

private struct ConfettiParticle {
    static let lifetime: Double = 3.4
    // Tuned so a burst from mid-screen spreads edge to edge without leaving
    // it, and pieces drift down at ~250pt/s instead of dropping like stones.
    private static let gravity: Double = 800
    private static let drag: Double = 3.2

    /// Data colors only - the same greens, golds and teals the scores wear.
    private static let palette: [Color] = [
        AppColors.scoreHigh, AppColors.scoreGood, AppColors.warning,
        AppColors.categoryBrandBright, AppColors.scoreLow, AppColors.info, .white
    ]

    enum Shape { case chip, ribbon, dot }

    let vx: Double
    let vy: Double
    let delay: Double
    let size: CGSize
    let shape: Shape
    let color: Color
    let spin: Double
    let flipRate: Double
    let phase: Double
    let sway: Double

    static func burst(count: Int) -> [ConfettiParticle] {
        (0..<count).map { _ in
            // A fan that opens upward, so pieces climb, hang, then flutter down.
            let angle = Double.random(in: -1...1)
            let speed = Double.random(in: 500...1300)
            let shape: Shape = [.chip, .chip, .chip, .ribbon, .dot].randomElement() ?? .chip
            let size: CGSize = switch shape {
            case .chip: CGSize(width: .random(in: 7...11), height: .random(in: 4...6))
            case .ribbon: CGSize(width: .random(in: 3...4), height: .random(in: 12...17))
            case .dot: CGSize(width: 6, height: 6)
            }
            return ConfettiParticle(
                // Squashed sideways so the fan stays on a phone-width screen.
                vx: 0.7 * speed * sin(angle),
                vy: -speed * cos(angle),
                delay: .random(in: 0...0.14),
                size: size,
                shape: shape,
                color: palette.randomElement() ?? .white,
                spin: .random(in: -9...9),
                flipRate: .random(in: 5...13),
                phase: .random(in: 0...(2 * .pi)),
                sway: .random(in: 6...22)
            )
        }
    }

    func draw(in context: GraphicsContext, from origin: CGPoint, at time: Double) {
        let t = time - delay
        guard t > 0 else { return }

        // v' = g - k·v  →  closed-form position under gravity and drag.
        let k = Self.drag, g = Self.gravity
        let decay = 1 - exp(-k * t)
        let x = Double(origin.x) + vx / k * decay
            + sway * min(1, t / 0.7) * sin(3.2 * t + phase)
        let y = Double(origin.y) + g / k * t + (vy - g / k) / k * decay

        let fadeStart = Self.lifetime - 0.9
        let opacity = t < fadeStart ? 1 : max(0, 1 - (t - fadeStart) / 0.9)
        guard opacity > 0 else { return }

        var piece = context
        piece.opacity = opacity
        piece.translateBy(x: CGFloat(x), y: CGFloat(y))
        piece.rotate(by: .radians(phase + spin * t))
        // Paper tumbling in 3D reads as one axis breathing through zero.
        if shape != .dot {
            piece.scaleBy(x: 1, y: CGFloat(max(0.08, abs(cos(flipRate * t + phase)))))
        }

        let rect = CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2), size: size)
        let path = shape == .dot
            ? Path(ellipseIn: rect)
            : Path(roundedRect: rect, cornerRadius: 1)
        piece.fill(path, with: .color(color))
    }
}

#Preview {
    struct Demo: View {
        @State private var run = 0
        var body: some View {
            ZStack {
                AppBackground()
                ConfettiView().id(run)
                GlassButton(title: "Again", style: .secondary) { run += 1 }
            }
        }
    }
    return Demo()
}

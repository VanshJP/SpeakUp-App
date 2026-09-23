import SwiftUI

/// The breathing orb, with the current step's elapsed share drawn as a ring
/// around it.
///
/// Scale is computed from accumulated phase time (`TimelineView`, paused when
/// paused) - never `withAnimation`, which cannot be cancelled and desyncs from
/// the clock (practice-tools invariant 16).
///
/// Each step animates from wherever the orb actually is to `toScale`, and the
/// phase clock restarts on `stepID`, not on the kind of step. It used to
/// restart only when the *kind* changed, so two inhales in a row - the
/// physiological sigh's second sniff - left the orb parked at full for the
/// whole top-up.
struct BreathingAnimationView: View {
    /// Where the orb should be when this step ends: 0.6 empty ... 1.0 full.
    let toScale: CGFloat
    let isRunning: Bool
    var duration: TimeInterval = 4.0
    /// Changes on every step, including two steps of the same kind in a row.
    var stepID: Int = 0
    var tint: Color = AppColors.primary
    var diameter: CGFloat = 240
    /// Shows the step ring. Off in the lead-in, which has no step yet.
    var showsRing: Bool = true

    static let emptyScale: CGFloat = 0.6

    /// 0...1 through the current step.
    @State private var phaseElapsed: Double = 0
    /// The scale the step started from - the orb's real position at the
    /// moment the step changed, so a clock that ran a frame long never jumps.
    @State private var startScale: CGFloat = BreathingAnimationView.emptyScale
    /// The scale last drawn. `onChange(of: stepID)` already sees the next
    /// step's target, so the handover has to start from this, not recompute.
    @State private var shownScale: CGFloat = BreathingAnimationView.emptyScale
    /// Last frame timestamp within a running stretch. Nil'd on every
    /// run-start so a resumed timeline never charges the paused gap.
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRunning)) { context in
            orb
                .onChange(of: context.date) { _, date in
                    guard isRunning else { return }
                    if let previous = lastTick, duration > 0 {
                        let delta = date.timeIntervalSince(previous)
                        phaseElapsed = min(phaseElapsed + delta / duration, 1)
                    }
                    lastTick = date
                    shownScale = currentScale
                }
        }
        .onChange(of: stepID) { _, newStep in
            // Back to step 0 is a restart: the orb empties rather than
            // carrying the last round's breath into the first inhale.
            startScale = newStep == 0 ? Self.emptyScale : shownScale
            shownScale = startScale
            phaseElapsed = 0
            lastTick = nil
        }
        .onChange(of: isRunning) { _, running in
            if running { lastTick = nil }
        }
    }

    private var orb: some View {
        let scale = currentScale
        let ringDiameter = diameter * 0.92

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.34), .clear],
                        center: .center,
                        startRadius: diameter * 0.18,
                        endRadius: diameter * 0.5
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(scale)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.7), AppColors.categoryBrandBright.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
                .frame(width: diameter * 0.62, height: diameter * 0.62)
                .scaleEffect(scale)

            if showsRing {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 4)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .trim(from: 0, to: phaseElapsed)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringDiameter, height: ringDiameter)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var currentScale: CGFloat {
        let eased = easeInOut(phaseElapsed)
        return startScale + (toScale - startScale) * eased
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    /// Where the orb should be at the end of each step: full after an inhale,
    /// empty after an exhale, unchanged across a hold. An inhale followed by
    /// another inhale stops short so the top-up has somewhere left to go, and
    /// the same for two exhales in a row.
    static func targets(for steps: [ExerciseStep]) -> [CGFloat] {
        var level: CGFloat = 0.6
        return steps.indices.map { index in
            let next = steps.indices.contains(index + 1) ? steps[index + 1].animation : nil
            switch steps[index].animation {
            case .expand: level = next == .expand ? 0.85 : 1.0
            case .contract: level = next == .contract ? 0.8 : 0.6
            case .hold: break
            }
            return level
        }
    }
}

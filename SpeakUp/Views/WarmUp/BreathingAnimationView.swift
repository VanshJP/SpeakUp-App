import SwiftUI

/// The breathing circle. Scale is *computed* from accumulated phase time, not
/// driven by `withAnimation` — an in-flight animation cannot be cancelled in
/// SwiftUI, so the old version kept breathing while the countdown was paused
/// and completed a second early every phase. Computed progress freezes with
/// `isRunning`, stays frozen before Start, and restarts deterministically.
struct BreathingAnimationView: View {
    let animation: StepAnimation
    let isRunning: Bool
    var duration: TimeInterval = 4.0

    /// Time through the current phase, normalized 0…1. Only advances while
    /// running, so pause/resume lands exactly where it left off.
    @State private var phaseElapsed: Double = 0
    /// Scale the previous phase ended on; holds freeze here.
    @State private var lastScale: CGFloat = 0.6
    /// Last frame timestamp within a running stretch. Nil'd on every
    /// run-start so a resumed timeline never charges the paused gap.
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRunning)) { context in
            circle
                .onChange(of: context.date) { _, date in
                    guard isRunning else { return }

                    if let previous = lastTick, duration > 0 {
                        let delta = date.timeIntervalSince(previous)
                        phaseElapsed = min(phaseElapsed + delta / duration, 1)
                    }
                    lastTick = date

                    lastScale = currentScale
                }
        }
        .onChange(of: animation) { _, _ in
            // New phase, fresh journey from its own start scale.
            phaseElapsed = 0
            lastTick = nil
            lastScale = currentScale
        }
        .onChange(of: isRunning) { _, running in
            if running {
                lastTick = nil
            } else {
                lastScale = currentScale
            }
        }
        .onAppear {
            // Frozen at the phase's start until Start is pressed.
            lastScale = phaseStartScale
        }
    }

    private var circle: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.primary.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(currentScale)

            // Inner circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.primary.opacity(0.6), AppColors.categoryBrandBright.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .scaleEffect(currentScale)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                        .scaleEffect(currentScale)
                }
        }
    }

    /// Where this phase's scale journey starts and ends. Holds keep whatever
    /// scale the previous phase ended on.
    private var phaseStartScale: CGFloat {
        switch animation {
        case .expand: return 0.6
        case .hold: return lastScale
        case .contract: return 1.0
        }
    }

    private var phaseEndScale: CGFloat {
        switch animation {
        case .expand: return 1.0
        case .hold: return lastScale
        case .contract: return 0.6
        }
    }

    private var currentScale: CGFloat {
        let eased = easeInOut(phaseElapsed)
        return phaseStartScale + (phaseEndScale - phaseStartScale) * eased
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}

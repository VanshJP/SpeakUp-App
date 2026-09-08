import SwiftUI

struct BreathingAnimationView: View {
    let animation: StepAnimation
    let isRunning: Bool
    var duration: TimeInterval = 4.0

    @State private var phaseElapsed: Double = 0
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
            lastScale = phaseStartScale
        }
    }

    private var circle: some View {
        ZStack {
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

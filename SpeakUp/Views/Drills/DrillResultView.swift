import SwiftUI

struct DrillResultView: View {
    let result: DrillResult
    /// Runs the same length again.
    let onTryAgain: () -> Void
    /// Runs the next rung up. Offered only when the result has one.
    var onLonger: (() -> Void)? = nil
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ring sweeps and the number climbs on arrival - the same count-up
    /// and odometer ticks as the session reveal, sized for a 30-second rep.
    @State private var counted = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RingProgress(
                    progress: counted ? Double(result.score) / 100 : 0,
                    color: result.passed ? AppColors.success : AppColors.error,
                    lineWidth: 8
                )
                .frame(width: 140, height: 140)

                VStack(spacing: 4) {
                    CountUpText(
                        value: counted ? Double(result.score) : 0,
                        font: .system(size: 44, weight: .bold, design: .rounded)
                    )

                    // A verdict, not an instruction: "Try again" here sat right
                    // above a Try again button.
                    Text(result.passed ? "Passed" : "Not yet")
                        .eyebrowStyle(result.passed ? AppColors.success : AppColors.error)
                }
            }

            Text(result.details)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Drills used to forget every run the moment this screen closed,
            // so there was never anything to beat.
            if let milestone = result.milestone {
                StatusPill(
                    text: milestone,
                    color: AppColors.success,
                    glyph: .icon("arrow.up.right")
                )
            }

            Spacer()

            VStack(spacing: 12) {
                // A cleared round offers the longer one as the next step and
                // keeps the same length a tap away. The ladder used to climb
                // behind "Try again", so the button that said "again" quietly
                // ran a longer round, and there was no way to repeat the one
                // just cleared.
                if let longer = result.longerRoundSeconds, let onLonger {
                    GlassButton(
                        title: "Go \(longer)s",
                        icon: "arrow.up.right",
                        style: .primary,
                        size: .large,
                        fullWidth: true
                    ) {
                        Haptics.medium()
                        onLonger()
                    }
                    .accessibilityLabel("Go longer: \(longer) seconds")

                    GlassButton(
                        title: "Repeat \(result.roundSeconds)s",
                        icon: "arrow.clockwise",
                        style: .secondary,
                        size: .large,
                        fullWidth: true
                    ) {
                        onTryAgain()
                    }
                    .accessibilityLabel("Repeat the \(result.roundSeconds)-second round")
                } else {
                    GlassButton(title: "Try again", style: .primary, size: .large, fullWidth: true) {
                        onTryAgain()
                    }
                }

                GlassButton(title: "Done", style: .secondary, size: .large, fullWidth: true) {
                    onDone()
                }
            }
            .padding(.bottom, 20)
        }
        .task { await reveal() }
    }

    private func reveal() async {
        guard !reduceMotion else {
            counted = true
            landingHaptic()
            return
        }
        withAnimation(.easeOut(duration: 0.9)) { counted = true }
        async let ticking: Void = Haptics.playCountUp(to: result.score, duration: 0.9, cutoff: 0.8)
        try? await Task.sleep(for: .milliseconds(850))
        await ticking
        guard !Task.isCancelled else { return }
        landingHaptic()
    }

    private func landingHaptic() {
        if result.passed { Haptics.success() } else { Haptics.light() }
    }
}

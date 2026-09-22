import SwiftUI

struct DrillResultView: View {
    let result: DrillResult
    let onTryAgain: () -> Void
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

                    Text(result.passed ? "Passed" : "Try again")
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
                Label(milestone, systemImage: "arrow.up.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.success)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.success.opacity(0.14))
                    }
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                GlassButton(title: "Try again", style: .primary, size: .large, fullWidth: true) {
                    onTryAgain()
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

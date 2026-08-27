import SwiftUI

struct DrillResultView: View {
    let result: DrillResult
    let onTryAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Score circle
            ZStack {
                RingProgress(
                    progress: Double(result.score) / 100,
                    color: result.passed ? AppColors.success : AppColors.error,
                    lineWidth: 8
                )
                .frame(width: 140, height: 140)

                VStack(spacing: 4) {
                    Text("\(result.score)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(result.passed ? "Passed" : "Try Again")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(result.passed ? AppColors.success : AppColors.error)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
            }

            // Details
            Text(result.details)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                GlassButton(title: "Try Again", style: .primary, size: .large, fullWidth: true) {
                    onTryAgain()
                }

                GlassButton(title: "Done", style: .secondary, size: .large, fullWidth: true) {
                    onDone()
                }
            }
            .padding(.bottom, 20)
        }
    }
}

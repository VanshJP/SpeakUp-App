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
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 8)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: Double(result.score) / 100)
                    .stroke(
                        result.passed ? AppColors.success : AppColors.error,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

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
                Button {
                    onTryAgain()
                } label: {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.white.opacity(0.94)))
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(GlassPressStyle())

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay { Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5) }
                        }
                }
                .buttonStyle(GlassPressStyle())
            }
            .padding(.bottom, 20)
        }
    }
}

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
                    .stroke(result.passed ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 8)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: Double(result.score) / 100)
                    .stroke(
                        result.passed ? Color.green : Color.red,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text("\(result.score)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(result.passed ? .green : .red)

                    Text(result.passed ? "Passed" : "Try Again")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(result.mode.color))
                }

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }
            }
            .padding(.bottom, 20)
        }
    }
}

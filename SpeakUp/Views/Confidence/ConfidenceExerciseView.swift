import SwiftUI

struct ConfidenceExerciseView: View {
    let exercise: ConfidenceExercise
    @Environment(\.dismiss) private var dismiss
    @State private var currentStepIndex = 0
    @State private var isComplete = false

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 32) {
                // Close button
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                }
                .padding(.top, 8)

                if isComplete {
                    completeContent
                } else {
                    stepContent
                }

                Spacer()

                navigationControls
            }
            .padding()
        }
    }

    // MARK: - Step Content

    private var stepContent: some View {
        VStack(spacing: 20) {
            Text(exercise.title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))

            Text("Step \(currentStepIndex + 1) of \(exercise.steps.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            // Step card
            VStack(spacing: 16) {
                Image(systemName: exercise.category.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(exercise.category.color)

                Text(exercise.steps[currentStepIndex])
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal)
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(exercise.category.color.opacity(0.08))
                    }
            }

            Spacer()

            ProgressView(value: Double(currentStepIndex + 1), total: Double(exercise.steps.count))
                .tint(exercise.category.color)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Complete

    private var completeContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("Well done!")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text("Take a moment to notice how you feel.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Navigation

    private var navigationControls: some View {
        VStack(spacing: 12) {
            if isComplete {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.teal))
                }
            } else {
                HStack(spacing: 12) {
                    if currentStepIndex > 0 {
                        Button {
                            ChirpPlayer.shared.play(.tick)
                            withAnimation { currentStepIndex -= 1 }
                        } label: {
                            Text("Back")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                        }
                    }

                    Button {
                        ChirpPlayer.shared.play(.tick)
                        withAnimation {
                            if currentStepIndex < exercise.steps.count - 1 {
                                currentStepIndex += 1
                            } else {
                                isComplete = true
                            }
                        }
                    } label: {
                        Text(currentStepIndex < exercise.steps.count - 1 ? "Next" : "Complete")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(exercise.category.color))
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }
}

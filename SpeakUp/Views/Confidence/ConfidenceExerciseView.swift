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
                    .accessibilityLabel("Close exercise")
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
            GlassCard(cornerRadius: 20, tint: exercise.category.color) {
                VStack(spacing: 16) {
                    Image(systemName: exercise.category.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(exercise.category.color)
                        .accessibilityHidden(true)

                    Text(exercise.step(safelyAt: currentStepIndex))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                // Re-identifying on the step index is what makes the swap
                // animate — a bare Text replacement snaps.
                .id(currentStepIndex)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            // One element: "Step 2 of 6" then the text, instead of a symbol
            // name announcement followed by an orphaned counter.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(currentStepIndex + 1) of \(exercise.steps.count)")
            .accessibilityValue(exercise.step(safelyAt: currentStepIndex))

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
                .foregroundStyle(AppColors.success)
                .accessibilityHidden(true)

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
                GlassButton(title: "Done", style: .primary, size: .large, fullWidth: true) {
                    dismiss()
                }
            } else {
                HStack(spacing: 12) {
                    if currentStepIndex > 0 {
                        GlassButton(title: "Back", style: .secondary, size: .large, fullWidth: true) {
                            ChirpPlayer.shared.play(.tick)
                            withAnimation(AppMotion.slide) { currentStepIndex -= 1 }
                        }
                    }

                    GlassButton(
                        title: currentStepIndex < exercise.steps.count - 1 ? "Next" : "Complete",
                        style: .primary,
                        size: .large,
                        fullWidth: true
                    ) {
                        withAnimation(AppMotion.slide) {
                            if currentStepIndex < exercise.steps.count - 1 {
                                currentStepIndex += 1
                                ChirpPlayer.shared.play(.tick)
                            } else {
                                isComplete = true
                                // Finishing used to sound identical to every
                                // step press — the "you did it" moment gets
                                // its own release breath and success haptic.
                                ChirpPlayer.shared.play(.exhale)
                                Haptics.success()
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }
}

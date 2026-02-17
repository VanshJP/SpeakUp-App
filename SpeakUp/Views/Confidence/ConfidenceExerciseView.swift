import SwiftUI

struct ConfidenceExerciseView: View {
    let exercise: ConfidenceExercise
    @Environment(\.dismiss) private var dismiss
    @State private var currentStepIndex = 0
    @State private var isComplete = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 24) {
                    // Title
                    VStack(spacing: 8) {
                        Image(systemName: exercise.category.icon)
                            .font(.largeTitle)
                            .foregroundStyle(exercise.category.color)

                        Text(exercise.title)
                            .font(.title2.weight(.bold))
                    }
                    .padding(.top)

                    if isComplete {
                        Spacer()

                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.green)

                            Text("Well done!")
                                .font(.title2.weight(.bold))

                            Text("You've completed this exercise. Take a moment to notice how you feel.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Spacer()

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
                        .padding(.horizontal)
                    } else {
                        // Progress
                        ProgressView(value: Double(currentStepIndex), total: Double(exercise.steps.count))
                            .tint(exercise.category.color)
                            .padding(.horizontal)

                        Text("Step \(currentStepIndex + 1) of \(exercise.steps.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Current step
                        GlassCard {
                            VStack(spacing: 12) {
                                // Pulse animation circle
                                Circle()
                                    .fill(exercise.category.color.opacity(0.15))
                                    .frame(width: 80, height: 80)
                                    .overlay {
                                        Text("\(currentStepIndex + 1)")
                                            .font(.title.weight(.bold))
                                            .foregroundStyle(exercise.category.color)
                                    }

                                Text(exercise.steps[currentStepIndex])
                                    .font(.title3.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.vertical, 8)
                        }
                        .padding(.horizontal)

                        Spacer()

                        // Navigation
                        HStack(spacing: 16) {
                            if currentStepIndex > 0 {
                                Button {
                                    withAnimation { currentStepIndex -= 1 }
                                } label: {
                                    Text("Back")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                                }
                            }

                            Button {
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
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

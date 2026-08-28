import SwiftUI
import UIKit

struct WarmUpExerciseView: View {
    var viewModel: WarmUpViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingExitConfirm = false

    /// Announces each step change to VoiceOver — the countdown numeral and
    /// the chirps are otherwise silent context for a non-visual reader.
    @State private var announcedStepIndex = -1

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 32) {
                // Close button
                HStack {
                    Button {
                        // Parity with the drill runner: an active session asks
                        // before it discards your progress.
                        if viewModel.isRunning {
                            Haptics.warning()
                            showingExitConfirm = true
                        } else {
                            viewModel.cleanup()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel("Close warm-up")
                    Spacer()
                }
                .padding(.top, 8)
                .confirmationDialog(
                    "End this warm-up?",
                    isPresented: $showingExitConfirm,
                    titleVisibility: .visible
                ) {
                    Button("End Warm-Up", role: .destructive) {
                        viewModel.cleanup()
                        dismiss()
                    }
                    Button("Keep Going", role: .cancel) {}
                } message: {
                    Text("Progress in this warm-up won't be saved.")
                }

                if viewModel.isComplete {
                    completeView
                } else {
                    exerciseContent
                }

                Spacer()

                if !viewModel.isComplete {
                    bottomControls
                }
            }
            .padding()
        }
        .onChange(of: viewModel.currentStepIndex) { _, newIndex in
            guard !viewModel.isComplete, newIndex != announcedStepIndex,
                  let step = viewModel.currentStep else { return }
            announcedStepIndex = newIndex
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(step.label), \(viewModel.timeRemaining) seconds"
            )
        }
    }

    // MARK: - Exercise Content

    private var exerciseContent: some View {
        VStack(spacing: 24) {
            Text(viewModel.currentExercise?.title ?? "")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))

            // Where you are in the exercise — the breathing circle carries
            // this visually, but a 12-step articulation drill had no position
            // affordance at all until this counter existed.
            VStack(spacing: 6) {
                Text("Step \(viewModel.currentStepIndex + 1) of \(viewModel.currentExercise?.steps.count ?? 0)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))

                ProgressView(
                    value: Double(viewModel.currentStepIndex + 1),
                    total: Double(max(1, viewModel.currentExercise?.steps.count ?? 1))
                )
                .tint(viewModel.currentExercise?.category.color)
                .padding(.horizontal, 40)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(viewModel.currentStepIndex + 1) of \(viewModel.currentExercise?.steps.count ?? 0)")

            if let step = viewModel.currentStep {
                if viewModel.currentExercise?.category == .breathing {
                    BreathingAnimationView(
                        animation: step.animation,
                        isRunning: viewModel.isRunning,
                        duration: TimeInterval(step.durationSeconds)
                    )
                    .accessibilityHidden(true)
                }

                Text(step.label)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("\(viewModel.timeRemaining)")
                    .font(.displayNumeral)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: viewModel.timeRemaining)
                    .accessibilityLabel("\(viewModel.timeRemaining) seconds remaining")
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Rounds picker (breathing only, before start)
            if viewModel.canCustomizeRounds,
               viewModel.currentStepIndex == 0,
               !viewModel.isRunning {
                roundsPicker
            }

            HStack(spacing: 32) {
                Button { viewModel.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .accessibilityLabel("Restart exercise")

                Button {
                    if viewModel.isRunning { viewModel.pause() } else { viewModel.start() }
                } label: {
                    Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color.white.opacity(0.94)))
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.isRunning)
                .accessibilityLabel(viewModel.isRunning ? "Pause" : "Start")

                Button { viewModel.skip() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .accessibilityLabel("Skip step")
            }
        }
        .padding(.bottom, 20)
    }

    private var roundsPicker: some View {
        HStack {
            Text("Rounds")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Button {
                if viewModel.selectedRounds > 1 {
                    viewModel.rebuildWithRounds(viewModel.selectedRounds - 1)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.15)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Fewer rounds")

            Text("\(viewModel.selectedRounds)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, alignment: .center)
                .contentTransition(.numericText())
                .animation(.default, value: viewModel.selectedRounds)

            Button {
                if viewModel.selectedRounds < 10 {
                    viewModel.rebuildWithRounds(viewModel.selectedRounds + 1)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.15)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More rounds")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        // One swipe adjusts; no need to hunt for the tiny −/+ buttons.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rounds")
        .accessibilityValue("\(viewModel.selectedRounds)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                viewModel.rebuildWithRounds(min(viewModel.selectedRounds + 1, 10))
            case .decrement:
                viewModel.rebuildWithRounds(max(viewModel.selectedRounds - 1, 1))
            @unknown default:
                break
            }
        }
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppColors.success)
                .accessibilityHidden(true)

            Text("Exercise Complete!")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text("Great warm-up! You're ready to speak.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            VStack(spacing: 12) {
                GlassButton(title: "Done", style: .primary, size: .large, fullWidth: true) {
                    viewModel.cleanup()
                    dismiss()
                }

                GlassButton(title: "Go Again", icon: "arrow.clockwise", style: .secondary, fullWidth: true) {
                    viewModel.goAgain()
                }
            }
        }
    }
}

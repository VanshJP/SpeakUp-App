import SwiftUI

struct WarmUpExerciseView: View {
    var viewModel: WarmUpViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 32) {
                // Close button
                HStack {
                    Button {
                        viewModel.cleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                }
                .padding(.top, 8)

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
    }

    // MARK: - Exercise Content

    private var exerciseContent: some View {
        VStack(spacing: 24) {
            Text(viewModel.currentExercise?.title ?? "")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))

            if let step = viewModel.currentStep {
                if viewModel.currentExercise?.category == .breathing {
                    BreathingAnimationView(
                        animation: step.animation,
                        isRunning: viewModel.isRunning,
                        duration: TimeInterval(step.durationSeconds)
                    )
                }

                Text(step.label)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("\(viewModel.timeRemaining)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: viewModel.timeRemaining)
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

                Button {
                    if viewModel.isRunning { viewModel.pause() } else { viewModel.start() }
                } label: {
                    Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(.teal))
                        .shadow(color: .teal.opacity(0.4), radius: 8, y: 2)
                }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.isRunning)

                Button { viewModel.skip() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.ultraThinMaterial))
                }
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
            }

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
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("Exercise Complete!")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text("Great warm-up! You're ready to speak.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Button {
                viewModel.cleanup()
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.teal))
            }
        }
    }
}

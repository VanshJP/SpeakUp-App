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
            }
            .padding()
        }
    }

    private var exerciseContent: some View {
        VStack(spacing: 32) {
            // Exercise title
            Text(viewModel.currentExercise?.title ?? "")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Spacer()

            // Breathing animation or step label
            if let step = viewModel.currentStep {
                if viewModel.currentExercise?.category == .breathing {
                    BreathingAnimationView(
                        animation: step.animation,
                        isRunning: viewModel.isRunning
                    )
                }

                Text(step.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Timer
                Text("\(viewModel.timeRemaining)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: viewModel.timeRemaining)
            }

            Spacer()

            // Progress indicator
            ProgressView(value: viewModel.progress)
                .tint(.teal)
                .padding(.horizontal, 40)

            // Controls
            HStack(spacing: 32) {
                Button {
                    viewModel.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.ultraThinMaterial))
                }

                Button {
                    if viewModel.isRunning {
                        viewModel.pause()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(.teal))
                        .shadow(color: .teal.opacity(0.4), radius: 8, y: 2)
                }

                Button {
                    viewModel.skip()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }
        }
    }

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Exercise Complete!")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text("Great warm-up! You're ready to speak.")
                .font(.body)
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

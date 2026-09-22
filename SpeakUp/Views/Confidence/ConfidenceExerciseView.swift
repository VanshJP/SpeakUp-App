import SwiftUI

struct ConfidenceExerciseView: View {
    let exercise: ConfidenceExercise
    @Environment(\.dismiss) private var dismiss
    @State private var currentStepIndex = 0
    @State private var isComplete = false

    /// Reads each step aloud, holds, and moves on by itself.
    ///
    /// Grounding and visualization both open with "close your eyes" - and then
    /// asked you to open them again to read the next step and find the Next
    /// button, every step. Guided mode keeps the eyes shut. Next and Back still
    /// work underneath it.
    @State private var isGuided = false
    @State private var voice = PronunciationService()
    /// How far through the current step's hold guided mode is, 0...1.
    @State private var holdProgress: Double = 0
    /// Guidance took over the audio session at some point, so leaving has to
    /// hand it back. An exercise run by hand never touches the session.
    @State private var didUseGuidance = false

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 32) {
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

                    if !isComplete {
                        guideToggle
                    }
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
        // Guided mode runs hands-free and eyes-closed for minutes at a time.
        .keepsScreenAwake(!isComplete)
        .task(id: guidedStepKey) {
            await runGuidedStep()
        }
        .onChange(of: isGuided) { _, guided in
            if !guided {
                voice.stop()
                holdProgress = 0
            }
        }
        .onDisappear {
            if didUseGuidance {
                voice.endGuidance()
            } else {
                voice.stop()
            }
        }
    }

    // MARK: - Guided mode

    private var guideToggle: some View {
        Button {
            Haptics.light()
            isGuided.toggle()
        } label: {
            Label(
                isGuided ? "Guided" : "Guide me",
                systemImage: isGuided ? "speaker.wave.2.fill" : "speaker.wave.2"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isGuided ? exercise.category.color : .white)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .accessibilityLabel(isGuided ? "Stop reading steps aloud" : "Read each step aloud and move on automatically")
    }

    /// Restarts the guided loop whenever the step changes by any route - the
    /// loop's own advance, Next, Back - or guidance is switched.
    private var guidedStepKey: String {
        "\(isGuided)-\(currentStepIndex)-\(isComplete)"
    }

    /// Speak the step, wait for the line to finish, hold, advance. Cancelled
    /// by any change to `guidedStepKey`, so a manual Next never double-steps.
    private func runGuidedStep() async {
        guard isGuided, !isComplete else { return }
        holdProgress = 0
        didUseGuidance = true

        await voice.prepareForGuidance()
        guard !Task.isCancelled else { return }
        voice.speak(text: exercise.step(safelyAt: currentStepIndex), rate: 0.45)

        // Bounded, so a synthesiser that never reports finishing cannot stall
        // the exercise.
        var waited = 0.0
        while voice.isSpeaking, waited < 20 {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            waited += 0.2
        }

        let ticks = exercise.guidedHoldSeconds * 10
        for tick in 1...ticks {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            holdProgress = Double(tick) / Double(ticks)
        }
        advance()
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
                .id(currentStepIndex)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(currentStepIndex + 1) of \(exercise.steps.count)")
            .accessibilityValue(exercise.step(safelyAt: currentStepIndex))

            if isGuided {
                ProgressView(value: holdProgress)
                    .tint(exercise.category.color.opacity(0.7))
                    .padding(.horizontal, 60)
                    .accessibilityLabel("Time on this step")
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
                        advance()
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func advance() {
        withAnimation(AppMotion.slide) {
            if currentStepIndex < exercise.steps.count - 1 {
                currentStepIndex += 1
                ChirpPlayer.shared.play(.tick)
            } else {
                isComplete = true
                PracticeRoutineService.shared.complete(.calm)
                ChirpPlayer.shared.play(.exhale)
                Haptics.success()
            }
        }
    }
}

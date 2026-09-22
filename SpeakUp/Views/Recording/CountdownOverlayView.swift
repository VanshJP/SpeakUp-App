import SwiftUI
import SwiftData

struct CountdownOverlayView: View {
    let prompt: Prompt?
    let duration: RecordingDuration
    let countdownDuration: Int
    let countdownStyle: CountdownStyle
    var look: TimerLook = .ring
    var backdrop: RecordingBackdrop = .base
    var prepTitle: String? = nil
    var prepSubtitle: String? = nil
    let onComplete: () -> Void
    let onCancel: () -> Void
    @Binding var selectedGoalId: UUID?
    var challenge: SharedChallenge? = nil

    @Query(filter: #Predicate<UserGoal> { !$0.isCompleted })
    private var activeGoals: [UserGoal]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var elapsedSeconds: Int = 0
    @State private var isPulsing: Bool = false
    @State private var hasCompleted: Bool = false

    private var totalSeconds: Int { countdownDuration }

    private var displayNumber: Int {
        switch countdownStyle {
        case .countDown:
            return max(0, totalSeconds - elapsedSeconds)
        case .countUp:
            return elapsedSeconds
        }
    }

    private var remainingSeconds: Int {
        max(0, totalSeconds - elapsedSeconds)
    }

    /// Changes only across the final three seconds, so only those beats kick.
    private var finalBeat: Int {
        reduceMotion || remainingSeconds > 3 ? 0 : remainingSeconds
    }

    init(
        prompt: Prompt?,
        duration: RecordingDuration,
        countdownDuration: Int = 15,
        countdownStyle: CountdownStyle = .countDown,
        look: TimerLook = .ring,
        backdrop: RecordingBackdrop = .base,
        prepTitle: String? = nil,
        prepSubtitle: String? = nil,
        selectedGoalId: Binding<UUID?> = .constant(nil),
        challenge: SharedChallenge? = nil,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.duration = duration
        self.countdownDuration = countdownDuration
        self.countdownStyle = countdownStyle
        self.look = look
        self.backdrop = backdrop
        self.prepTitle = prepTitle
        self.prepSubtitle = prepSubtitle
        self._selectedGoalId = selectedGoalId
        self.challenge = challenge
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            RecordingBackdropView(backdrop: backdrop)

            VStack(spacing: 16) {
                if let prompt {
                    prominentPromptCard(prompt)
                }

                if let prepTitle {
                    VStack(spacing: 4) {
                        Text(prepTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if let prepSubtitle, !prepSubtitle.isEmpty {
                            Text(prepSubtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5)
                            }
                    }
                    .accessibilityElement(children: .combine)
                }

                SessionDialSlot { diameter in
                    TimerDial(
                        look: look,
                        progress: progress,
                        text: "\(displayNumber)",
                        caption: "sec",
                        isPulsing: isPulsing,
                        diameter: diameter
                    )
                    // The last three seconds land as beats: the dial kicks
                    // on the same tick as the heavy haptic.
                    .keyframeAnimator(initialValue: 1.0, trigger: finalBeat) { dial, scale in
                        dial.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(1.1, duration: 0.12, spring: .snappy)
                            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                        }
                    }
                }

                HStack(spacing: 12) {
                    GlassButton(
                        title: "Cancel",
                        icon: "xmark",
                        style: .secondary,
                        size: .medium,
                        fullWidth: true
                    ) {
                        cancelCountdown()
                    }

                    GlassButton(
                        title: "Start Now",
                        icon: "bolt.fill",
                        style: .primary,
                        size: .medium,
                        fullWidth: true
                    ) {
                        skipCountdown()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await runCountdown()
        }
        .ambientLoop(AppMotion.ambient(duration: 1.0)) { isPulsing = true }
        .onAppear {
            if selectedGoalId == nil, let firstGoal = activeGoals.first {
                selectedGoalId = firstGoal.id
            }
        }
    }

    // MARK: - Countdown loop

    /// Finishes on the tick that reaches the end. It used to wait one more
    /// full second parked on "0" before starting, so every countdown ran a
    /// second longer than the setting said - the drift the warm-up timer
    /// already fixed for itself.
    @MainActor
    private func runCountdown() async {
        while !Task.isCancelled, elapsedSeconds < totalSeconds {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, !hasCompleted else { return }

            withAnimation(.easeInOut(duration: 0.3)) {
                elapsedSeconds += 1
            }

            if remainingSeconds == 0 {
                break
            } else if remainingSeconds <= 3 {
                Haptics.heavy()
            } else {
                Haptics.light()
            }
        }
        guard !Task.isCancelled else { return }
        finishCountdown()
    }

    // MARK: - Actions

    private func cancelCountdown() {
        guard !hasCompleted else { return }
        hasCompleted = true
        Haptics.light()
        onCancel()
    }

    private func skipCountdown() {
        guard !hasCompleted else { return }
        hasCompleted = true
        Haptics.success()
        onComplete()
    }

    private func finishCountdown() {
        guard !hasCompleted else { return }
        hasCompleted = true
        Haptics.success()
        onComplete()
    }

    // MARK: - Prominent Prompt Card

    private func prominentPromptCard(_ prompt: Prompt) -> some View {
        FeaturedGlassCard {
            VStack(spacing: 16) {
                if challenge != nil {
                    Text("Friend challenge")
                        .eyebrowStyle(AppColors.primary)
                        .frame(maxWidth: .infinity)
                }

                HStack {
                    Label(prompt.category, systemImage: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Text(prompt.difficulty.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(AppColors.difficultyColor(prompt.difficulty).opacity(0.3))
                        }
                        .foregroundStyle(AppColors.difficultyColor(prompt.difficulty))

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(duration.displayName)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(.white.opacity(0.1))
                    }
                }

                Text(prompt.text)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text(challengeFooter)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    private var challengeFooter: String {
        if let score = challenge?.beatScore {
            return "They scored \(score). Your turn, same prompt, your pace."
        }
        if challenge != nil {
            return "A friend sent you this prompt"
        }
        return "Read and prepare your response"
    }

    // MARK: - Helpers

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        switch countdownStyle {
        case .countDown:
            return Double(remainingSeconds) / Double(totalSeconds)
        case .countUp:
            return Double(elapsedSeconds) / Double(totalSeconds)
        }
    }
}

#Preview {
    CountdownOverlayView(
        prompt: nil,
        duration: .sixty,
        countdownDuration: 15,
        onComplete: {},
        onCancel: {}
    )
}

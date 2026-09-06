import SwiftUI
import SwiftData

struct CountdownOverlayView: View {
    let prompt: Prompt?
    let duration: RecordingDuration
    let countdownDuration: Int
    let countdownStyle: CountdownStyle
    var look: TimerLook = .ring
    var backdrop: RecordingBackdrop = .base
    /// Optional context line for flows that prep for a named format rather
    /// than read a prompt — drills show the mode and what it costs. nil keeps
    /// the recording layout byte-identical.
    var prepTitle: String? = nil
    var prepSubtitle: String? = nil
    let onComplete: () -> Void
    let onCancel: () -> Void
    @Binding var selectedGoalId: UUID?
    /// Set when this session came from a friend-challenge link.
    var challenge: SharedChallenge? = nil

    @Query(filter: #Predicate<UserGoal> { !$0.isCompleted })
    private var activeGoals: [UserGoal]

    @State private var elapsedSeconds: Int = 0
    @State private var isPulsing: Bool = false
    @State private var hasCompleted: Bool = false

    private var totalSeconds: Int { countdownDuration }

    /// The number displayed in the timer circle.
    private var displayNumber: Int {
        switch countdownStyle {
        case .countDown:
            return max(0, totalSeconds - elapsedSeconds)
        case .countUp:
            return elapsedSeconds
        }
    }

    /// Remaining seconds until completion (used for haptic timing).
    private var remainingSeconds: Int {
        max(0, totalSeconds - elapsedSeconds)
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

            // Laid out against the recording screen, slot for slot: prompt
            // where the compact prompt card will be, dial where the clock will
            // be and at the clock's size, actions along the bottom. The
            // hand-off used to drop the dial from the top of the screen to the
            // middle and grow it 150 → 200, so the one thing the eye was
            // holding onto moved the instant recording started.
            VStack(spacing: 20) {
                if let prompt {
                    prominentPromptCard(prompt)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 0)

                // Prep context for prompt-less flows (drills): what you
                // picked and what it costs — or, for impromptu, the topic to
                // start thinking about.
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

                TimerDial(
                    look: look,
                    progress: progress,
                    text: "\(displayNumber)",
                    caption: "sec",
                    isPulsing: isPulsing,
                    diameter: 200
                )

                Spacer(minLength: 0)

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
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
            .padding(.top, 50)
        }
        // Full-screen covers and root overlays must own the hit surface —
        // without this, a parent scroll / LazyVStack can eat the first few
        // taps while layout settles (Cancel felt dead until ~7 on a 10s clock).
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task {
            // `.task` cancels on disappear, so Cancel cannot race a stray tick
            // the way the old `Timer.publish` View-`let` could.
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

    @MainActor
    private func runCountdown() async {
        // One cancellable loop instead of `Timer.publish` as a View `let` —
        // that publisher was recreated on every body refresh and raced Cancel.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, !hasCompleted else { return }

            if elapsedSeconds < totalSeconds {
                withAnimation(.easeInOut(duration: 0.3)) {
                    elapsedSeconds += 1
                }

                if remainingSeconds <= 3 && remainingSeconds > 0 {
                    Haptics.heavy()
                } else {
                    Haptics.light()
                }
            } else {
                finishCountdown()
                return
            }
        }
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                        .textCase(.uppercase)
                        .tracking(0.8)
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

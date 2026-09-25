import SwiftUI
import SwiftData

/// The prepare screen before a take. It names what the take is about - the
/// prompt card, or `prepTitle` when there is no prompt (a story, free talk, a
/// drill) - and it attaches nothing the user did not choose: it used to hand
/// every take to the first active goal, on a screen with no goal control.
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
    var challenge: SharedChallenge? = nil

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
                    .glassEffect(.regular, in: .capsule)
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
                        title: "Start now",
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

                // Category · difficulty as one eyebrow, the grammar of the
                // Today card and the Library rows. Difficulty was a filled
                // capsule here, the one place it still was.
                HStack(alignment: .center, spacing: 8) {
                    let category = PromptCategory(rawValue: prompt.category)

                    HStack(spacing: 5) {
                        Image(systemName: category?.iconName ?? "text.bubble")
                        Text(category?.shortName ?? prompt.category)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("·")
                        Text(prompt.difficulty.displayName)
                            .foregroundStyle(prompt.difficulty.color)
                    }
                    .eyebrowStyle(category?.color ?? AppColors.accent)
                    .layoutPriority(-1)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(duration.displayName)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    // Painted, not glass: it sits on the card's glass.
                    .background { Capsule().fill(Color.white.opacity(0.10)) }
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                    .fixedSize()
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

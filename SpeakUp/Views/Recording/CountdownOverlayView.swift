import SwiftUI
import SwiftData
import Combine

struct CountdownOverlayView: View {
    let prompt: Prompt?
    let duration: RecordingDuration
    let countdownDuration: Int
    let countdownStyle: CountdownStyle
    var look: CountdownLook = .ring
    var backdrop: RecordingBackdrop = .base
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
            return totalSeconds - elapsedSeconds
        case .countUp:
            return elapsedSeconds
        }
    }

    /// Remaining seconds until completion (used for haptic timing).
    private var remainingSeconds: Int {
        totalSeconds - elapsedSeconds
    }

    init(
        prompt: Prompt?,
        duration: RecordingDuration,
        countdownDuration: Int = 15,
        countdownStyle: CountdownStyle = .countDown,
        look: CountdownLook = .ring,
        backdrop: RecordingBackdrop = .base,
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
        self._selectedGoalId = selectedGoalId
        self.challenge = challenge
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            RecordingBackdropView(backdrop: backdrop)

            VStack(spacing: 20) {
                CountdownDial(
                    look: look,
                    progress: progress,
                    number: displayNumber,
                    isPulsing: isPulsing
                )
                .padding(.top, 60)

                Spacer()

                if let prompt {
                    prominentPromptCard(prompt)
                        .padding(.horizontal, 20)
                }

                Spacer()

                HStack(spacing: 12) {
                    GlassButton(
                        title: "Cancel",
                        icon: "xmark",
                        style: .secondary,
                        size: .medium,
                        fullWidth: true
                    ) {
                        onCancel()
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
        }
        .onReceive(timer) { _ in
            guard !hasCompleted else { return }
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
                hasCompleted = true
                Haptics.success()
                onComplete()
            }
        }
        .ambientLoop(AppMotion.ambient(duration: 1.0)) { isPulsing = true }
        .onAppear {
            if selectedGoalId == nil, let firstGoal = activeGoals.first {
                selectedGoalId = firstGoal.id
            }
        }
    }

    // MARK: - Actions

    private func skipCountdown() {
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
            return "They scored \(score). Can you beat it?"
        }
        if challenge != nil {
            return "A friend sent you this prompt"
        }
        return "Read and prepare your response"
    }

    // MARK: - Helpers
    
    private var progress: Double {
        switch countdownStyle {
        case .countDown:
            return Double(remainingSeconds) / Double(totalSeconds)
        case .countUp:
            return Double(elapsedSeconds) / Double(totalSeconds)
        }
    }
}

// MARK: - Countdown Dial

/// The countdown visual on its own, so the settings picker previews exactly
/// what the countdown screen will show.
struct CountdownDial: View {
    let look: CountdownLook
    let progress: Double
    let number: Int
    var isPulsing: Bool = false

    private let segmentCount = 12

    var body: some View {
        ZStack {
            switch look {
            case .ring:
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 140, height: 140)
                    .scaleEffect(isPulsing ? 1.06 : 1.0)

                RingProgress(progress: progress, color: AppColors.primary, lineWidth: 5)
                    .frame(width: 110, height: 110)
                    .motion(.linear(duration: 1), value: progress)

                numberStack(size: 40, showsUnit: true)

            case .orb:
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.primary.opacity(0.55), AppColors.primary.opacity(0.02)],
                            center: .center,
                            startRadius: 6,
                            endRadius: 78
                        )
                    )
                    .frame(width: 150, height: 150)
                    // The orb itself is the progress read-out: it shrinks as
                    // the countdown drains, so there is no ring to read.
                    .scaleEffect(0.72 + 0.28 * progress)
                    .motion(.linear(duration: 1), value: progress)

                numberStack(size: 46, showsUnit: false)

            case .segments:
                ZStack {
                    ForEach(0..<segmentCount, id: \.self) { i in
                        Capsule()
                            .fill(
                                Double(i) < progress * Double(segmentCount)
                                    ? AppColors.primary
                                    : Color.white.opacity(0.12)
                            )
                            .frame(width: 3, height: 14)
                            .offset(y: -62)
                            .rotationEffect(.degrees(Double(i) / Double(segmentCount) * 360))
                    }
                }
                .frame(width: 140, height: 140)

                numberStack(size: 40, showsUnit: true)

            case .minimal:
                VStack(spacing: 14) {
                    Text("\(number)")
                        .font(.system(size: 72, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.3), value: number)

                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 120, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(AppColors.primary)
                                .frame(width: 120 * progress, height: 3)
                                .motion(.linear(duration: 1), value: progress)
                        }
                }
                .frame(width: 140, height: 140)
            }
        }
        .frame(width: 150, height: 150)
    }

    private func numberStack(size: CGFloat, showsUnit: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(number)")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: number)

            if showsUnit {
                Text("sec")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1.0)
            }
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


import SwiftUI
import SwiftData
import Combine

struct CountdownOverlayView: View {
    let prompt: Prompt?
    let duration: RecordingDuration
    let countdownDuration: Int
    let countdownStyle: CountdownStyle
    let onComplete: () -> Void
    let onCancel: () -> Void
    @Binding var selectedGoalId: UUID?

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
        selectedGoalId: Binding<UUID?> = .constant(nil),
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.duration = duration
        self.countdownDuration = countdownDuration
        self.countdownStyle = countdownStyle
        self._selectedGoalId = selectedGoalId
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppBackground(style: .recording)

            VStack(spacing: 20) {
                countdownRing
                    .padding(.top, 60)

                Spacer()

                if let prompt {
                    prominentPromptCard(prompt)
                        .padding(.horizontal, 20)
                }

                Spacer()

                GeometryReader { geo in
                    HStack(spacing: 12) {
                        GlassButton(title: "Cancel", icon: "xmark", style: .secondary, size: .medium) {
                            onCancel()
                        }
                        .frame(width: (geo.size.width - 12) / 2, height: 48)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)

                        GlassButton(title: "Start Now", icon: "bolt.fill", style: .secondary, size: .medium) {
                            skipCountdown()
                        }
                        .frame(width: (geo.size.width - 12) / 2, height: 48)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 48)
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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
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

    // MARK: - Countdown Ring

    private var countdownRing: some View {
        ZStack {
            Circle()
                .fill(AppColors.primary.opacity(0.08))
                .frame(width: 140, height: 140)
                .scaleEffect(isPulsing ? 1.08 : 1.0)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 5)
                .frame(width: 110, height: 110)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.primary, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            VStack(spacing: 2) {
                Text("\(displayNumber)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: displayNumber)

                Text("sec")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Prominent Prompt Card

    private func prominentPromptCard(_ prompt: Prompt) -> some View {
        FeaturedGlassCard(
            gradientColors: [AppColors.primary.opacity(0.12), Color.cyan.opacity(0.06)]
        ) {
            VStack(spacing: 16) {
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

                Text("Read and prepare your response")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
            }
        }
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

#Preview {
    CountdownOverlayView(
        prompt: nil,
        duration: .sixty,
        countdownDuration: 15,
        onComplete: {},
        onCancel: {}
    )
}


import SwiftUI
import Combine

struct CountdownOverlayView: View {
    let prompt: Prompt?
    let duration: RecordingDuration
    let countdownDuration: Int
    let countdownStyle: CountdownStyle
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var elapsedSeconds: Int = 0
    @State private var isPulsing: Bool = false

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
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.duration = duration
        self.countdownDuration = countdownDuration
        self.countdownStyle = countdownStyle
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Fully opaque dark background to hide content behind
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Top: Compact timer badge (lowered)
                HStack {
                    Spacer()
                    compactTimer
                    Spacer()
                }
                .padding(.top, 100)

                Spacer()

                // Center: Large prominent prompt card
                if let prompt {
                    prominentPromptCard(prompt)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Bottom: Cancel button
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                }
                .padding(.bottom, 60)
            }
        }
        .onReceive(timer) { _ in
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
                Haptics.success()
                onComplete()
            }
        }
        .onAppear {
            // Start pulsing animation
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    // MARK: - Compact Timer

    private var compactTimer: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(Color.cyan.opacity(0.15))
                .frame(width: 100, height: 100)
                .scaleEffect(isPulsing ? 1.1 : 1.0)

            // Progress ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 4)
                .frame(width: 80, height: 80)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan, Color.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            // Timer number
            Text("\(displayNumber)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: displayNumber)
        }
    }
    
    // MARK: - Prominent Prompt Card

    private func prominentPromptCard(_ prompt: Prompt) -> some View {
        VStack(spacing: 16) {
            // Category + difficulty badges
            HStack {
                Label(prompt.category, systemImage: PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                // Difficulty badge
                Text(prompt.difficulty.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(AppColors.difficultyColor(prompt.difficulty).opacity(0.3))
                    }
                    .foregroundStyle(AppColors.difficultyColor(prompt.difficulty))

                // Duration pill
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
                        .fill(.white.opacity(0.15))
                }
            }

            // Large prompt text (main focus)
            Text(prompt.text)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Instruction hint
            Text("Read and prepare your response")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 8)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
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

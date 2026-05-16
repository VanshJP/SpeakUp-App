import SwiftUI

/// Redesigned interactive onboarding. Full-bleed cinematic pages, no pinned
/// bottom button bar, in-context permission prompts, mic test, reminder
/// scheduling, and resume-mid-flow support. Designed to get a brand-new user
/// from welcome to first recording in under 60 seconds.
struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Namespace private var orbNamespace

    var onComplete: (OnboardingResult) -> Void

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)
                .ignoresSafeArea()

            // Single brand-tinted ambient wash. Subtle so glass surfaces read.
            ambientGradient
                .ignoresSafeArea()
                .opacity(0.7)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ZStack {
                    stepContent
                        .id(viewModel.currentStep)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.35), value: viewModel.currentStep)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.checkMicPermission()
            viewModel.restoreFromDefaults()
            Task { await viewModel.checkNotificationPermission() }
        }
        .onChange(of: viewModel.currentStep) { oldStep, newStep in
            // Dismiss keyboard on every step transition. Steps that need the
            // keyboard (.name, .vocab) re-acquire focus themselves after the
            // crossfade settles.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
            // Centralised mic-test lifecycle so leaving via Back/Skip/Continue
            // always tears down the recording, and re-entering with permission
            // already granted re-arms the live waveform.
            if oldStep == .mic, newStep != .mic {
                viewModel.stopMicTest()
            }
            if newStep == .mic, oldStep != .mic, viewModel.hasMicPermission {
                Task { await viewModel.resumeMicTestIfPermitted() }
            }
        }
        .onDisappear {
            viewModel.stopMicTest()
        }
    }

    // MARK: - Ambient gradient

    /// Single static brand-tinted ambient wash. Locked to `AppColors.primary`
    /// so the palette stays calm — no per-step color shifts that previously
    /// made the flow feel rainbow-y.
    private var ambientGradient: some View {
        let tint = AppColors.primary
        return ZStack {
            RadialGradient(
                colors: [tint.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 60,
                endRadius: 480
            )
            RadialGradient(
                colors: [tint.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    /// Accent color used for the progress bar + selection highlights. Pinned
    /// to the brand primary instead of cycling per step.
    private var currentTint: Color { AppColors.primary }

    // MARK: - Top Bar (progress + back)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if viewModel.currentStep.allowsBack {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(10)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(.white.opacity(0.08)))
                        }
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 36, height: 36)
            }

            OnboardingProgressBar(
                progress: viewModel.stepProgress,
                tint: currentTint
            )

            // Skip is allowed everywhere except the terminal ready step where
            // it makes no sense — and welcome which already advances on tap.
            if viewModel.currentStep != .welcome && viewModel.currentStep != .ready {
                Button("Skip") {
                    viewModel.advance()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            } else {
                Color.clear.frame(width: 36, height: 12)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)
    }

    // MARK: - Step Routing

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingWelcomeStep(
                orbNamespace: orbNamespace,
                onContinue: viewModel.advance
            )
        case .toolkit:
            OnboardingToolkitStep(
                orbNamespace: orbNamespace,
                onContinue: viewModel.advance
            )
        case .name:
            OnboardingNameStep(
                orbNamespace: orbNamespace,
                name: Binding(
                    get: { viewModel.nameInput },
                    set: { viewModel.nameInput = $0 }
                ),
                canAdvance: viewModel.canAdvanceFromName,
                onContinue: viewModel.advance
            )
        case .goal:
            OnboardingGoalStep(
                orbNamespace: orbNamespace,
                userName: viewModel.trimmedName,
                selectedGoal: viewModel.selectedGoal,
                onSelect: { goal in
                    viewModel.selectGoal(goal)
                    // Auto-advance after a short beat so the user sees their
                    // pick highlighted before the page changes. Snapshot the
                    // pick so a quick re-tap on a different goal cancels the
                    // earlier pending advance.
                    let snapshot = goal
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard viewModel.currentStep == .goal,
                              viewModel.selectedGoal == snapshot else { return }
                        viewModel.advance()
                    }
                }
            )
        case .level:
            OnboardingLevelStep(
                orbNamespace: orbNamespace,
                selected: viewModel.speakerLevel,
                onSelect: { level in
                    viewModel.selectLevel(level)
                    let snapshot = level
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard viewModel.currentStep == .level,
                              viewModel.speakerLevel == snapshot else { return }
                        viewModel.advance()
                    }
                }
            )
        case .vocab:
            OnboardingVocabStep(
                orbNamespace: orbNamespace,
                vocabWords: viewModel.vocabWords,
                onAdd: { viewModel.addVocabWord($0) },
                onRemove: { viewModel.removeVocabWord($0) },
                onContinue: viewModel.advance
            )
        case .mic:
            OnboardingMicStep(
                orbNamespace: orbNamespace,
                hasPermission: viewModel.hasMicPermission,
                isRequesting: viewModel.isRequestingMicPermission,
                level: viewModel.micLevel,
                heardVoice: viewModel.hasHeardVoice,
                onEnable: {
                    Task { await viewModel.requestMicAndStartTest() }
                },
                onContinue: viewModel.advance
            )
        case .reminder:
            OnboardingReminderStep(
                orbNamespace: orbNamespace,
                hasPermission: viewModel.hasNotificationPermission,
                isRequesting: viewModel.isRequestingNotificationPermission,
                reminderEnabled: Binding(
                    get: { viewModel.reminderEnabled },
                    set: { viewModel.reminderEnabled = $0 }
                ),
                reminderTime: Binding(
                    get: { viewModel.reminderTime },
                    set: { viewModel.reminderTime = $0 }
                ),
                onEnable: {
                    Task { await viewModel.requestNotificationPermission() }
                },
                onContinue: viewModel.advance,
                onSkip: {
                    viewModel.reminderEnabled = false
                    viewModel.advance()
                }
            )
        case .ready:
            OnboardingReadyStep(
                orbNamespace: orbNamespace,
                userName: viewModel.trimmedName,
                goal: viewModel.selectedGoal ?? .everydayConfidence,
                level: viewModel.speakerLevel,
                launchFirstRecording: Binding(
                    get: { viewModel.launchFirstRecording },
                    set: { viewModel.launchFirstRecording = $0 }
                ),
                onFinish: {
                    Haptics.success()
                    onComplete(viewModel.makeResult())
                }
            )
        }
    }

    private var stepTransition: AnyTransition {
        // Pure opacity crossfade so the shared brand orb (matchedGeometry)
        // can morph between positions without the whole page sliding around.
        .opacity
    }
}

// MARK: - Progress Bar

private struct OnboardingProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, geo.size.width * progress))
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Shared Orb

/// The brand orb used as a visual anchor across steps. The shared namespace
/// is accepted but no longer drives matchedGeometryEffect — combining it with
/// `.id`-based step swaps caused the orb to jitter mid-transition. Each step
/// now renders its own orb sized for that page; continuity comes from the
/// gentle pulse + opacity crossfade between pages.
private struct OnboardingOrb: View {
    let size: CGFloat
    var glowColor: Color = .teal
    let namespace: Namespace.ID
    var pulses: Bool = true

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Image("BigTalkOrb")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: glowColor.opacity(0.55), radius: size * 0.18, y: 6)
            .shadow(color: glowColor.opacity(0.30), radius: size * 0.40, y: 12)
            .scaleEffect(pulseScale)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.04
                }
            }
            .animation(.easeInOut(duration: 0.6), value: glowColor)
    }
}

// MARK: - Welcome

private struct OnboardingWelcomeStep: View {
    let orbNamespace: Namespace.ID
    let onContinue: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            OnboardingOrb(size: 220, glowColor: .teal, namespace: orbNamespace)

            VStack(spacing: 14) {
                Text("Speak with confidence")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)

                Text("Your private, on-device speech coach.\nLet's get you set up in under a minute.")
                    .font(.system(size: 16, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(4)
                    .opacity(subtitleOpacity)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                // Trust badges sit above the CTA so the user reads the value
                // proposition before the action — the previous order buried
                // them below the button where they were missed entirely.
                HStack(spacing: 18) {
                    OnboardingTrustBadge(icon: "lock.shield.fill", text: "On-device")
                    OnboardingTrustBadge(icon: "wifi.slash", text: "Offline OK")
                    OnboardingTrustBadge(icon: "hand.raised.fill", text: "Private")
                }

                Button(action: onContinue) {
                    HStack(spacing: 10) {
                        Text("Begin")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background {
                        Capsule().fill(AppColors.primary)
                    }
                    .shadow(color: AppColors.primary.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            }
            .opacity(ctaOpacity)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.15)) { titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) { subtitleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.45).delay(0.55)) { ctaOpacity = 1 }
        }
    }
}

private struct OnboardingTrustBadge: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.primary)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Name Step

private struct OnboardingNameStep: View {
    let orbNamespace: Namespace.ID
    @Binding var name: String
    let canAdvance: Bool
    let onContinue: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(size: 110, glowColor: AppColors.primary, namespace: orbNamespace)
                .padding(.top, 16)

            VStack(spacing: 10) {
                Text("What should I call you?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Type your name. We'll add it to the on-device dictionary so transcripts spell it right when you say it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 28)

            TextField("", text: $name, prompt: Text("Your name").foregroundStyle(.white.opacity(0.35)))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit {
                    if canAdvance { onContinue() }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(
                                    focused ? AppColors.primary.opacity(0.55) : Color.white.opacity(0.10),
                                    lineWidth: focused ? 1.5 : 0.5
                                )
                        }
                }
                .shadow(color: focused ? AppColors.primary.opacity(0.18) : .clear, radius: 18, y: 8)
                .padding(.horizontal, 24)
                .padding(.top, 32)

            Spacer(minLength: 0)

            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text(canAdvance ? "Nice to meet you" : "Type to continue")
                        .font(.system(size: 16, weight: .semibold))
                    if canAdvance {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    Capsule()
                        .fill(canAdvance
                              ? AnyShapeStyle(AppColors.primary)
                              : AnyShapeStyle(.ultraThinMaterial))
                }
                .opacity(canAdvance ? 1 : 0.6)
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .animation(.easeInOut(duration: 0.2), value: canAdvance)
        }
        .task {
            // Wait for the page transition to settle before raising the
            // keyboard, otherwise the focus animation collides with the
            // crossfade. `.task` is auto-cancelled if the view disappears.
            try? await Task.sleep(for: .milliseconds(420))
            focused = true
        }
    }
}

// MARK: - Goal Step

private struct OnboardingGoalStep: View {
    let orbNamespace: Namespace.ID
    let userName: String
    let selectedGoal: OnboardingGoal?
    let onSelect: (OnboardingGoal) -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(size: 90, glowColor: AppColors.primary, namespace: orbNamespace)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text(greeting)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Why did you download Big Talk? Pick the closest fit — we'll tune your daily prompts to match. You can change this later in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(OnboardingGoal.allCases) { goal in
                        OnboardingGoalCard(
                            goal: goal,
                            isSelected: selectedGoal == goal
                        ) {
                            onSelect(goal)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private var greeting: String {
        userName.isEmpty ? "What brought you here?" : "What brought you here, \(userName)?"
    }
}

private struct OnboardingGoalCard: View {
    let goal: OnboardingGoal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(goal.color.opacity(isSelected ? 0.32 : 0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: goal.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(goal.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(goal.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? goal.color : .white.opacity(0.25))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isSelected ? goal.color.opacity(0.55) : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    }
            }
            .shadow(color: isSelected ? goal.color.opacity(0.20) : .clear, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Level Step

private struct OnboardingLevelStep: View {
    let orbNamespace: Namespace.ID
    let selected: SpeakerLevel
    let onSelect: (SpeakerLevel) -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(size: 90, glowColor: AppColors.primary, namespace: orbNamespace)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text("How would you describe yourself?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("We'll mix daily prompts to match. Change anytime in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 16)

            VStack(spacing: 12) {
                ForEach(SpeakerLevel.allCases) { level in
                    OnboardingLevelCard(
                        level: level,
                        isSelected: selected == level
                    ) {
                        onSelect(level)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            PromptMixCard(weights: selected.dailyDifficultyWeights)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
    }
}

struct OnboardingLevelCard: View {
    let level: SpeakerLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(level.color.opacity(isSelected ? 0.32 : 0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: level.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(level.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(level.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(level.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? level.color : .white.opacity(0.25))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isSelected ? level.color.opacity(0.55) : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    }
            }
            .shadow(color: isSelected ? level.color.opacity(0.20) : .clear, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Daily Prompt Mix readout. Replaces the prior tiny stacked-segment bar
/// (which clipped its labels and abused layoutPriority for sizing) with a
/// per-difficulty row showing label, percentage, and a proportional bar —
/// far easier to scan at a glance.
struct PromptMixCard: View {
    let weights: (easy: Int, medium: Int, hard: Int)

    private var total: Int {
        max(1, weights.easy + weights.medium + weights.hard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                Text("Your daily prompt mix")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            VStack(spacing: 10) {
                PromptMixRow(label: "Easy", count: weights.easy, total: total, color: .green)
                PromptMixRow(label: "Medium", count: weights.medium, total: total, color: .orange)
                PromptMixRow(label: "Hard", count: weights.hard, total: total, color: .red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: total)
    }
}

struct PromptMixRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    private var fraction: Double {
        Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 56, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 8)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Mic Step

private struct OnboardingMicStep: View {
    let orbNamespace: Namespace.ID
    let hasPermission: Bool
    let isRequesting: Bool
    let level: Float
    let heardVoice: Bool
    let onEnable: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(
                size: 110,
                glowColor: hasPermission ? AppColors.success : AppColors.primary,
                namespace: orbNamespace
            )
            .padding(.top, 12)

            VStack(spacing: 10) {
                Text(hasPermission ? "Say something" : "Let's hear your voice")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 24)

            // Live waveform — bars react to mic level.
            OnboardingWaveform(level: level)
                .frame(height: 120)
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .opacity(hasPermission ? 1 : 0.35)

            if heardVoice {
                Label("Sounds great!", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.top, 16)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 0)

            if hasPermission {
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text(heardVoice ? "Continue" : "Continue anyway")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        Capsule().fill(heardVoice ? AppColors.success : AppColors.primary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            } else {
                Button(action: onEnable) {
                    HStack(spacing: 10) {
                        if isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(isRequesting ? "Asking..." : "Enable mic & speech")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        Capsule().fill(AppColors.primary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }

            Text("100% on-device. Audio never leaves your phone.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
    }

    private var subtitle: String {
        if !hasPermission {
            return "We need mic access to record and speech recognition for transcription. Both are used only while you practice."
        }
        if heardVoice {
            return "Mic is working. Keep talking or continue."
        }
        return "Try saying: \"Hi, I'm getting started with Big Talk.\""
    }
}

private struct OnboardingWaveform: View {
    let level: Float
    private let barCount = 28

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { i in
                    BarView(index: i, total: barCount, level: level, geoHeight: geo.size.height)
                }
            }
        }
    }

    private struct BarView: View {
        let index: Int
        let total: Int
        let level: Float
        let geoHeight: CGFloat
        @State private var phase: Double = 0

        var body: some View {
            let position = Double(index) / Double(total - 1)
            // Distance from middle (0 at center, 1 at edges). Centre bars react more.
            let distance = abs(position - 0.5) * 2
            let centerWeight = 1 - distance * 0.7
            let noise = (sin(phase + Double(index) * 0.4) + 1) / 2
            let amplitude = max(0.05, Double(level)) * centerWeight * (0.6 + noise * 0.6)
            let height = max(6, CGFloat(amplitude) * geoHeight)
            return Capsule()
                .fill(AppColors.primary)
                .frame(height: height)
                .frame(maxHeight: .infinity, alignment: .center)
                .onAppear {
                    withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                        phase = .pi * 2
                    }
                }
        }
    }
}

// MARK: - Reminder Step

private struct OnboardingReminderStep: View {
    let orbNamespace: Namespace.ID
    let hasPermission: Bool
    let isRequesting: Bool
    @Binding var reminderEnabled: Bool
    @Binding var reminderTime: Date
    let onEnable: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(size: 100, glowColor: AppColors.primary, namespace: orbNamespace)
                .padding(.top, 12)

            VStack(spacing: 10) {
                Text("Stay on track")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("One nudge a day. Pick the time. Skip if you'd rather not.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 24)

            VStack(spacing: 16) {
                if hasPermission {
                    HStack {
                        Toggle(isOn: $reminderEnabled) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundStyle(AppColors.primary)
                                Text("Daily practice nudge")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .tint(AppColors.primary)
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.white.opacity(0.08))
                            }
                    }

                    // Wheel picker needs ~200pt to render its three rolling
                    // rows without clipping. Prior 130pt cap squashed the
                    // wheel and blocked the centre row's hit region — taps
                    // would land off-target. Padding kept minimal so the
                    // wheel's own internal hit-testing isn't shadowed by the
                    // material card.
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 196)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white.opacity(0.08))
                                }
                        }
                        .opacity(reminderEnabled ? 1 : 0.4)
                        .disabled(!reminderEnabled)
                } else {
                    Button(action: onEnable) {
                        HStack(spacing: 10) {
                            if isRequesting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(isRequesting ? "Asking..." : "Enable reminders")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background {
                            Capsule().fill(AppColors.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text(hasPermission ? "Looks good" : "Continue without")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        Capsule().fill(AppColors.primary)
                    }
                }
                .buttonStyle(.plain)

                if hasPermission {
                    Button("No thanks", action: onSkip)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Ready Step

private struct OnboardingReadyStep: View {
    let orbNamespace: Namespace.ID
    let userName: String
    let goal: OnboardingGoal
    let level: SpeakerLevel
    @Binding var launchFirstRecording: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(size: 160, glowColor: AppColors.primary, namespace: orbNamespace)
                .padding(.top, 24)

            VStack(spacing: 10) {
                Text(headline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Your setup is ready. Tap below to start your first practice session.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 28)

            VStack(spacing: 10) {
                ReadySummaryRow(icon: goal.icon, label: "Focus", value: goal.displayName, tint: goal.color)
                ReadySummaryRow(icon: level.icon, label: "Level", value: level.displayName, tint: level.color)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Toggle(isOn: $launchFirstRecording) {
                    Text("Start a 60-second session right now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .tint(AppColors.primary)
                .padding(.horizontal, 20)

                Button(action: onFinish) {
                    HStack(spacing: 10) {
                        Image(systemName: launchFirstRecording ? "mic.fill" : "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(launchFirstRecording ? "Start first recording" : "Take me in")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background {
                        Capsule().fill(AppColors.primary)
                    }
                    .shadow(color: AppColors.primary.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
    }

    private var headline: String {
        userName.isEmpty ? "You're all set" : "Let's go, \(userName)"
    }
}

private struct ReadySummaryRow: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
        }
    }
}

// MARK: - Toolkit Step

/// Restored feature showcase. Sits between welcome and name so the user sees
/// what they're signing up for before answering questions. Three glass tiles
/// summarise the toolkit at a glance — recording, scoring, and curated
/// practice surfaces.
private struct OnboardingToolkitStep: View {
    let orbNamespace: Namespace.ID
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(size: 100, glowColor: AppColors.primary, namespace: orbNamespace)
                .padding(.top, 12)

            VStack(spacing: 10) {
                Text("Your speaking toolkit")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Everything you need to improve, in one private app.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 22)

            VStack(spacing: 10) {
                ToolkitFeatureRow(icon: "waveform", title: "Record & score", subtitle: "Multi-dimensional speech analysis with clarity, pace, and filler tracking.")
                ToolkitFeatureRow(icon: "books.vertical.fill", title: "Drills & stories", subtitle: "Curated warm-ups, drills, read-aloud passages, and your own scripts.")
                ToolkitFeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Track progress", subtitle: "Daily streaks, weekly summaries, and side-by-side then-vs-now replays.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Spacer(minLength: 0)

            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    Capsule().fill(AppColors.primary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct ToolkitFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.primary.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
        }
    }
}


// MARK: - Vocab Step

/// Vocabulary introduction. Shows the seeded power-word list as removable
/// chips and lets the user add their own. Words flow into the user's word
/// bank on completion so vocabulary scoring rewards usage of these terms.
private struct OnboardingVocabStep: View {
    let orbNamespace: Namespace.ID
    let vocabWords: [String]
    let onAdd: (String) -> Bool
    let onRemove: (String) -> Void
    let onContinue: () -> Void

    @State private var newWord: String = ""
    @State private var dictationEngine = DictationService()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOrb(size: 90, glowColor: AppColors.primary, namespace: orbNamespace)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Your power vocabulary")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("These words boost your vocabulary score when you use them. We've seeded a starter set for your level — add your own or remove any you don't want.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        TextField("", text: $newWord, prompt: Text("Add a word").foregroundStyle(.white.opacity(0.4)))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($inputFocused)
                            .onSubmit(commitNewWord)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                inputFocused ? AppColors.primary.opacity(0.55) : Color.white.opacity(0.10),
                                                lineWidth: inputFocused ? 1.2 : 0.5
                                            )
                                    }
                            }

                        Button(action: toggleDictation) {
                            ZStack {
                                Circle()
                                    .fill(dictationEngine.isListening
                                          ? AppColors.primary.opacity(0.25) : .white.opacity(0.06))
                                    .overlay {
                                        Circle().strokeBorder(
                                            dictationEngine.isListening
                                            ? AppColors.primary.opacity(0.6) : .white.opacity(0.1),
                                            lineWidth: 0.5)
                                    }
                                    .frame(width: 44, height: 44)
                                Image(systemName: dictationEngine.isListening ? "mic.fill" : "mic")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(dictationEngine.isListening
                                                     ? AppColors.primary : .white.opacity(0.5))
                                    .symbolEffect(.pulse, isActive: dictationEngine.isListening)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: commitNewWord) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle().fill(canAdd ? AnyShapeStyle(AppColors.primary) : AnyShapeStyle(.ultraThinMaterial))
                                }
                                .opacity(canAdd ? 1 : 0.5)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAdd)
                    }

                    if dictationEngine.isListening, !dictationEngine.recognizedWords.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(dictationEngine.recognizedWords.enumerated()), id: \.offset) { _, word in
                                Text(word)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background {
                                        Capsule()
                                            .fill(AppColors.primary.opacity(0.15))
                                            .overlay {
                                                Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                                            }
                                    }
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.spring(duration: 0.25), value: dictationEngine.recognizedWords.count)
                    }

                    if vocabWords.isEmpty {
                        Text("No words yet. Add a few to bias scoring toward the language you want to use more often.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.vertical, 4)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(vocabWords, id: \.self) { word in
                                VocabChip(word: word, onRemove: { onRemove(word) })
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }

            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    Capsule().fill(AppColors.primary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .onDisappear {
            dictationEngine.stop()
        }
    }

    private var canAdd: Bool {
        !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commitNewWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if onAdd(trimmed) {
            newWord = ""
        }
    }

    private func toggleDictation() {
        if dictationEngine.isListening {
            let words = dictationEngine.recognizedWords
            dictationEngine.stop()
            for word in words { _ = onAdd(word) }
        } else {
            dictationEngine.recognizedWords = []
            dictationEngine.lastAddedIndex = 0
            Haptics.medium()
            Task { await dictationEngine.start() }
        }
    }
}

private struct VocabChip: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .background {
                        Circle().fill(.white.opacity(0.12))
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(AppColors.primary.opacity(0.22))
                .overlay {
                    Capsule().strokeBorder(AppColors.primary.opacity(0.45), lineWidth: 0.8)
                }
        }
    }
}

import SwiftUI

// MARK: - Welcome

/// Hero step. Runs its own centred layout rather than `OnboardingPage`. This
/// is the one screen that should feel like a cover, not a form.
struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            OnboardingOrb(size: 200)

            VStack(spacing: 12) {
                Text("Big Talk")
                    .eyebrowStyle()
                    .opacity(titleOpacity)

                Text("Hear yourself improve.")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(titleOpacity)

                Text("Speak for a minute a day. Big Talk listens, scores, and coaches, all on this iPhone.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(subtitleOpacity)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 24)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            VStack(spacing: 16) {
                // Three pills fit one row at default type and on the narrowest
                // phone, but not at accessibility sizes, so fall back to two rows
                // rather than letting them clip.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        onDevicePill
                        offlinePill
                        noAccountPill
                    }
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            onDevicePill
                            offlinePill
                        }
                        noAccountPill
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("On-device, works offline, no account required")

                OnboardingCTA(title: "Let's start", action: onContinue)

                Text("About two minutes, and it ends with your first score.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(ctaOpacity)
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.15)) { titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) { subtitleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.45).delay(0.55)) { ctaOpacity = 1 }
        }
    }

    // MARK: - Subviews

    private var onDevicePill: some View {
        StatusPill(text: "On-device", color: AppColors.primary, glyph: .icon("lock.fill"))
    }

    private var offlinePill: some View {
        StatusPill(text: "Works offline", color: AppColors.primary, glyph: .icon("wifi.slash"))
    }

    private var noAccountPill: some View {
        StatusPill(text: "No account", color: AppColors.primary, glyph: .icon("person.fill.xmark"))
    }
}

// MARK: - Name

struct OnboardingNameStep: View {
    let counter: String?
    @Binding var name: String
    let canAdvance: Bool
    let onContinue: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "What should we call you?",
            subtitle: "Stays on this iPhone."
        ) {
            GlassCard(padding: 6, accentBorder: focused ? AppColors.primary : nil) {
                TextField(
                    "",
                    text: $name,
                    prompt: Text("Your name").foregroundStyle(.white.opacity(0.3))
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit {
                    if canAdvance { onContinue() }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
            }
        } footer: {
            OnboardingCTA(
                title: canAdvance ? "Continue" : "Type your name",
                icon: canAdvance ? "arrow.right" : nil,
                isEnabled: canAdvance,
                action: onContinue
            )
        }
        .task {
            // Wait for the page crossfade to settle before raising the
            // keyboard, otherwise the focus animation collides with it.
            try? await Task.sleep(for: .milliseconds(420))
            focused = true
        }
    }
}

// MARK: - Goal

/// One question, one tap. Picking a card surfaces an immediate payoff line —
/// proof the app listened — and the flow advances on its own; the answer is
/// the navigation. Under VoiceOver the auto-advance is replaced by an
/// explicit Continue, since unrequested navigation is disorienting there.
struct OnboardingGoalStep: View {
    let counter: String?
    let userName: String
    let selectedGoal: OnboardingGoal?
    let onSelect: (OnboardingGoal, _ autoAdvance: Bool) -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: title
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingGoal.allCases) { goal in
                    OnboardingChoiceCard(
                        title: goal.displayName,
                        subtitle: goal.subtitle,
                        isSelected: selectedGoal == goal
                    ) {
                        onSelect(goal, !voiceOverEnabled)
                    }
                    .opacity(cardOpacity(for: goal))
                }
            }
            .motion(AppMotion.snap, value: selectedGoal)

            if let goal = selectedGoal {
                payoffLine(payoff(for: goal))
            }
        } footer: {
            if voiceOverEnabled {
                OnboardingCTA(
                    title: "Continue",
                    isEnabled: selectedGoal != nil,
                    action: onContinue
                )
            }
        }
        .motion(AppMotion.settle, value: selectedGoal)
    }

    private var title: String {
        userName.isEmpty ? "What brought you here?" : "What brought you here, \(userName)?"
    }

    private func cardOpacity(for goal: OnboardingGoal) -> Double {
        guard let selectedGoal else { return 1 }
        return goal == selectedGoal ? 1 : 0.55
    }

    private func payoff(for goal: OnboardingGoal) -> String {
        switch goal {
        case .interviews: return "Got it. Expect interview-style questions."
        case .meetings: return "Got it. Prompts will lean toward meetings and updates."
        case .presentations: return "Got it. Expect prompts you could open a talk with."
        case .everydayConfidence: return "Got it. Prompts will feel like everyday conversation."
        case .storytelling: return "Got it. Expect stories to tell and retell."
        }
    }
}

// MARK: - Level

/// Reframed from an assessment ("Beginner / Advanced") to a feelings question
/// — self-grading is exactly the anxiety this flow removes. Answers still map
/// onto `SpeakerLevel`, which drives prompt difficulty and vocab seeding.
struct OnboardingLevelStep: View {
    let counter: String?
    let selected: SpeakerLevel?
    let onSelect: (SpeakerLevel, _ autoAdvance: Bool) -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "How do you feel about speaking today?"
        ) {
            VStack(spacing: 10) {
                ForEach(SpeakerLevel.allCases) { level in
                    OnboardingChoiceCard(
                        title: feelingTitle(for: level),
                        subtitle: feelingSubtitle(for: level),
                        isSelected: selected == level
                    ) {
                        onSelect(level, !voiceOverEnabled)
                    }
                    .opacity(cardOpacity(for: level))
                }
            }
            .motion(AppMotion.snap, value: selected)

            if let level = selected {
                payoffLine(payoff(for: level))
            }
        } footer: {
            if voiceOverEnabled {
                OnboardingCTA(
                    title: "Continue",
                    isEnabled: selected != nil,
                    action: onContinue
                )
            }
        }
        .motion(AppMotion.settle, value: selected)
    }

    private func cardOpacity(for level: SpeakerLevel) -> Double {
        guard let selected else { return 1 }
        return level == selected ? 1 : 0.55
    }

    private func feelingTitle(for level: SpeakerLevel) -> String {
        switch level {
        case .beginner: return "Finding my feet"
        case .intermediate: return "Getting comfortable"
        case .advanced: return "Sharpening up"
        }
    }

    private func feelingSubtitle(for level: SpeakerLevel) -> String {
        switch level {
        case .beginner: return "I avoid speaking when I can."
        case .intermediate: return "I'm fine. I want to be good."
        case .advanced: return "I'm good. I'm chasing great."
        }
    }

    private func payoff(for level: SpeakerLevel) -> String {
        switch level {
        case .beginner: return "We'll start you gentle and ramp up."
        case .intermediate: return "We'll start you on mostly medium prompts."
        case .advanced: return "We'll skew your prompts hard."
        }
    }
}

// MARK: - Shared

/// The "it listened" line under a choice list. `id` keys the transition so a
/// re-pick crossfades instead of mutating in place.
private func payoffLine(_ text: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(AppColors.success)
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 4)
    .id(text)
    .transition(.opacity.combined(with: .offset(y: 6)))
    .accessibilityElement(children: .combine)
}

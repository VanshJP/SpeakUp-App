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

/// One question, up to three answers. Multi-select because the situations
/// overlap in real life — interviews *and* everyday confidence is one person —
/// and because the picks weight the prompt mix rather than choosing one lane.
///
/// Nothing auto-advances. A step that jumps a beat after the first tap makes a
/// second pick a race against a timer, so the user says when they're done.
struct OnboardingGoalStep: View {
    let counter: String?
    let userName: String
    let selectedGoals: [OnboardingGoal]
    let maxGoals: Int
    let onToggle: (OnboardingGoal) -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: title,
            subtitle: "Pick up to \(maxGoals). Your daily prompts lean this way."
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingGoal.allCases) { goal in
                    OnboardingChoiceCard(
                        title: goal.displayName,
                        subtitle: goal.subtitle,
                        isSelected: selectedGoals.contains(goal)
                    ) {
                        onToggle(goal)
                    }
                    .opacity(cardOpacity(for: goal))
                }
            }
            .motion(AppMotion.snap, value: selectedGoals)

            if !selectedGoals.isEmpty {
                payoffLine(payoff)
            }
        } footer: {
            OnboardingCTA(
                title: selectedGoals.isEmpty ? "Pick at least one" : "Continue",
                icon: selectedGoals.isEmpty ? nil : "arrow.right",
                isEnabled: !selectedGoals.isEmpty,
                action: onContinue
            )
        }
        .motion(AppMotion.settle, value: selectedGoals)
    }

    private var title: String {
        userName.isEmpty ? "What brought you here?" : "What brought you here, \(userName)?"
    }

    /// Unpicked cards dim only once the limit is reached, where the dimming is
    /// information ("these are out for now") rather than decoration. Dimming
    /// them from the first tap would read as four rejected answers.
    private func cardOpacity(for goal: OnboardingGoal) -> Double {
        if selectedGoals.contains(goal) { return 1 }
        return selectedGoals.count >= maxGoals ? 0.4 : 1
    }

    /// One line for the whole selection, not one per pick. Three stacked "Got
    /// it" lines is a receipt; the user needs to know the prompts moved.
    private var payoff: String {
        guard selectedGoals.count == 1, let goal = selectedGoals.first else {
            let names = selectedGoals.map(\.promptPayoffNoun)
            return "Got it. Expect a mix of \(names.joinedNaturally())."
        }
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
    let onSelect: (SpeakerLevel) -> Void
    let onContinue: () -> Void

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
                        onSelect(level)
                    }
                    .opacity(cardOpacity(for: level))
                }
            }
            .motion(AppMotion.snap, value: selected)

            if let level = selected {
                payoffLine(payoff(for: level))
            }
        } footer: {
            // Explicit Continue, same as the goal step. Single-choice or not,
            // one flow should not have two different ideas of what a tap does.
            OnboardingCTA(
                title: selected == nil ? "Pick one" : "Continue",
                icon: selected == nil ? nil : "arrow.right",
                isEnabled: selected != nil,
                action: onContinue
            )
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

private extension OnboardingGoal {
    /// Lower-case noun for the combined payoff line, which reads as one
    /// sentence rather than a list of headings.
    var promptPayoffNoun: String {
        switch self {
        case .interviews: return "interview questions"
        case .meetings: return "meeting moments"
        case .presentations: return "talk openers"
        case .everydayConfidence: return "everyday talk"
        case .storytelling: return "stories"
        }
    }
}

private extension Array where Element == String {
    /// "a", "a and b", "a, b, and c" — the goal step caps at three, so this
    /// never has to reason about longer lists.
    func joinedNaturally() -> String {
        switch count {
        case 0: return ""
        case 1: return self[0]
        case 2: return "\(self[0]) and \(self[1])"
        default:
            let head = dropLast().joined(separator: ", ")
            return "\(head), and \(self[count - 1])"
        }
    }
}

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

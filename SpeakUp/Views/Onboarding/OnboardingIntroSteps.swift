import SwiftUI

// MARK: - Welcome

/// Hero step. Runs its own centred layout rather than `OnboardingPage` — this
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

                Text("Practice out loud.\nHear yourself improve.")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(titleOpacity)

                Text("Big Talk listens while you practice, scores how you actually sound, and tells you what to fix next — all on this iPhone.")
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
                HStack(spacing: 8) {
                    StatusPill(text: "On-device", color: AppColors.primary, glyph: .icon("lock.fill"))
                    StatusPill(text: "Works offline", color: AppColors.primary, glyph: .icon("wifi.slash"))
                    StatusPill(text: "No account", color: AppColors.primary, glyph: .icon("person.slash.fill"))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("On-device, works offline, no account required")

                OnboardingCTA(title: "Get started", action: onContinue)

                Text("Takes about a minute. Everything is editable later in Settings.")
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
}

// MARK: - How It Works

/// The explainer the flow was missing. Covers the practice loop, what actually
/// gets measured, what else is in the app, and the privacy model — so a new
/// user knows what they are agreeing to before the questions start.
struct OnboardingHowItWorksStep: View {
    let counter: String?
    let onContinue: () -> Void

    private let features: [(icon: String, label: String)] = [
        ("text.bubble.fill", "Daily prompts"),
        ("lungs.fill", "Warm-ups"),
        ("target", "Focus drills"),
        ("book.pages.fill", "Read-aloud"),
        ("doc.richtext.fill", "Your own scripts"),
        ("graduationcap.fill", "Guided curriculum"),
        ("chart.line.uptrend.xyaxis", "Progress charts"),
        ("flame.fill", "Streaks & goals")
    ]

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "How Big Talk works",
            subtitle: "One short session is enough to get a full read on your speaking.",
            icon: "waveform.circle.fill"
        ) {
            GlassCard(tint: AppColors.glassTintPrimary, padding: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    OnboardingNumberedRow(
                        number: 1,
                        title: "Speak for 30–120 seconds",
                        detail: "Answer a prompt, run a drill, or free-practice. No script required."
                    )
                    OnboardingNumberedRow(
                        number: 2,
                        title: "Get scored, not just transcribed",
                        detail: "Your audio is transcribed on this device, then rated on clarity, pace, filler words, pause quality, vocal variety, vocabulary, structure, and how well you stayed on topic."
                    )
                    OnboardingNumberedRow(
                        number: 3,
                        title: "Fix one thing at a time",
                        detail: "Each session ends with specific tips, and you can replay your first take against today's to hear the difference."
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                GlassSectionHeader("What's inside", icon: "square.grid.2x2.fill")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(features, id: \.label) { feature in
                        featureTile(icon: feature.icon, label: feature.label)
                    }
                }
            }

            GlassCard(padding: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.success)
                    Text("Recordings, transcripts, and scores stay on your iPhone. No account, no server, works in airplane mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            OnboardingCTA(title: "Continue", action: onContinue)
        }
    }

    private func featureTile(icon: String, label: String) -> some View {
        GlassCard(padding: 11) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 18)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
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
            subtitle: "Your name is added to the on-device dictionary so transcripts spell it correctly when you say it out loud.",
            icon: "person.fill"
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

            Text("Stays on this device. Used for greetings and transcript accuracy only.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
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

struct OnboardingGoalStep: View {
    let counter: String?
    let userName: String
    let selectedGoal: OnboardingGoal?
    let onSelect: (OnboardingGoal) -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: title,
            subtitle: "Pick the closest fit. It shapes the prompts you see on Today and the tips you get after a session.",
            icon: "scope"
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingGoal.allCases) { goal in
                    OnboardingChoiceCard(
                        icon: goal.icon,
                        title: goal.displayName,
                        subtitle: goal.subtitle,
                        tint: goal.color,
                        isSelected: selectedGoal == goal
                    ) {
                        onSelect(goal)
                    }
                }
            }
        } footer: {
            OnboardingCTA(
                title: selectedGoal == nil ? "Pick a focus" : "Continue",
                icon: selectedGoal == nil ? nil : "arrow.right",
                isEnabled: selectedGoal != nil,
                action: onContinue
            )
        }
    }

    private var title: String {
        userName.isEmpty ? "What brought you here?" : "What brought you here, \(userName)?"
    }
}

// MARK: - Level

struct OnboardingLevelStep: View {
    let counter: String?
    let selected: SpeakerLevel
    let onSelect: (SpeakerLevel) -> Void
    let onContinue: () -> Void

    private var levelBinding: Binding<SpeakerLevel> {
        Binding(get: { selected }, set: { onSelect($0) })
    }

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "Where are you starting from?",
            subtitle: "This sets how hard your daily prompts are and which starter vocabulary we seed.",
            icon: "chart.bar.fill"
        ) {
            SectionPicker(
                sections: SpeakerLevel.allCases,
                selection: levelBinding,
                label: { $0.displayName }
            )

            GlassCard(tint: selected.color, padding: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        OnboardingGlyph(icon: selected.icon, tint: selected.color, size: 34)
                        Text(selected.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().overlay(AppColors.cardStroke)

                    PromptMixSummary(weights: selected.dailyDifficultyWeights)
                }
            }
            .motion(AppMotion.settle, value: selected)
        } footer: {
            OnboardingCTA(title: "Continue", action: onContinue)
        }
    }
}

/// Daily prompt difficulty split for the selected speaker level. One row per
/// band with a proportional meter, rather than a stacked bar whose labels
/// never fit.
struct PromptMixSummary: View {
    let weights: (easy: Int, medium: Int, hard: Int)

    private var total: Int {
        max(1, weights.easy + weights.medium + weights.hard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your daily prompt mix")
                .eyebrowStyle()

            PromptMixRow(label: "Easy", count: weights.easy, total: total, color: AppColors.success)
            PromptMixRow(label: "Medium", count: weights.medium, total: total, color: AppColors.warning)
            PromptMixRow(label: "Hard", count: weights.hard, total: total, color: AppColors.error)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Daily prompt mix: \(weights.easy) easy, \(weights.medium) medium, \(weights.hard) hard out of \(total)"
        )
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
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            TickMeter(fraction: fraction, color: color, tickCount: 20)
                .frame(height: 10)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}

// MARK: - Vocabulary

/// Seeds the word bank. Words here raise the vocabulary subscore when the
/// speaker actually uses them, so the copy has to say that plainly.
struct OnboardingVocabStep: View {
    let counter: String?
    let vocabWords: [String]
    let onAdd: (String) -> Bool
    let onRemove: (String) -> Void
    let onContinue: () -> Void

    @State private var newWord: String = ""
    @State private var dictationEngine = DictationService()
    @FocusState private var inputFocused: Bool

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "Words you want to use more",
            subtitle: "Using these in a session lifts your vocabulary score. We've seeded a starter set for your level — edit it however you like.",
            icon: "textformat.abc"
        ) {
            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    inputRow

                    if dictationEngine.isListening, !dictationEngine.recognizedWords.isEmpty {
                        heardWords
                    }

                    if vocabWords.isEmpty {
                        Text("No words yet. Add a few to bias scoring toward the language you want to reach for.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(vocabWords, id: \.self) { word in
                                VocabChip(word: word) { onRemove(word) }
                            }
                        }
                    }
                }
            }

            Text("Tap the mic to add words by speaking them. Manage the full word bank later in Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        } footer: {
            OnboardingCTA(title: "Continue", action: onContinue)
        }
        .onDisappear {
            dictationEngine.stop()
        }
    }

    // MARK: - Subviews

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $newWord,
                prompt: Text("Add a word").foregroundStyle(.white.opacity(0.35))
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($inputFocused)
            .onSubmit(commitNewWord)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(
                                inputFocused ? AppColors.primary.opacity(0.5) : AppColors.cardStroke,
                                lineWidth: inputFocused ? 1 : 0.5
                            )
                    }
            }

            circleButton(
                icon: dictationEngine.isListening ? "mic.fill" : "mic",
                isActive: dictationEngine.isListening,
                action: toggleDictation
            )
            .accessibilityLabel(dictationEngine.isListening ? "Stop dictation" : "Add words by voice")

            circleButton(icon: "plus", isActive: canAdd, action: commitNewWord)
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.45)
                .accessibilityLabel("Add word")
        }
    }

    private var heardWords: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(dictationEngine.recognizedWords.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(AppColors.primary.opacity(0.15))
                            .overlay { Capsule().strokeBorder(AppColors.cardStroke, lineWidth: 0.5) }
                    }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(AppMotion.snap, value: dictationEngine.recognizedWords.count)
    }

    private func circleButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? AppColors.primary : Color.white.opacity(0.55))
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(isActive ? AppColors.primary.opacity(0.18) : Color.white.opacity(0.05))
                        .overlay {
                            Circle().strokeBorder(
                                isActive ? AppColors.primary.opacity(0.5) : AppColors.cardStroke,
                                lineWidth: 0.5
                            )
                        }
                }
        }
        .buttonStyle(GlassPressStyle())
    }

    // MARK: - Actions

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

struct VocabChip: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .background { Circle().fill(.white.opacity(0.12)) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(word)")
        }
        .padding(.leading, 11)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(AppColors.primary.opacity(0.18))
                .overlay { Capsule().strokeBorder(AppColors.primary.opacity(0.4), lineWidth: 0.8) }
        }
    }
}

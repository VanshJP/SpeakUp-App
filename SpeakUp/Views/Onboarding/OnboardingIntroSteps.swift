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

                Text("Practice out loud.\nHear yourself improve.")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(titleOpacity)

                Text("Big Talk listens while you practice, scores how you actually sound, and tells you what to fix next, all on this iPhone.")
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

// MARK: - How It Works

/// Beat one of the explainer: what a single session actually is.
///
/// Laid out with `LessonPathRow`, the same node-and-rail the Learn tab uses for
/// a lesson path. A session is a sequence, so the rail carries the ordering the
/// numbered circles used to, and the beats sit straight on the canvas instead
/// of in three stacked cards.
///
/// Every node stays on the leading side rather than alternating like Learn
/// does. Alternating only works when labels are short enough to right-align
/// without looking stranded, and these carry real copy.
///
/// Copy is kept to one title line and two detail lines on purpose: the node is
/// a fixed 58pt, and a label taller than that pushes the rail away from the
/// node it is supposed to leave.
struct OnboardingHowItWorksStep: View {
    let counter: String?
    let onContinue: () -> Void

    private let beats: [(icon: String, title: String, detail: String)] = [
        ("mic.fill",
         "Speak for 30–120 seconds",
         "Answer a prompt, run a drill, or free-practice. No script required."),
        ("chart.bar.fill",
         "Get scored, not transcribed",
         "Transcribed on this device, then scored on clarity, pace, fillers, pauses and five more."),
        ("target",
         "Fix one thing at a time",
         "Specific tips after each session, and you can replay your first take against today's.")
    ]

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "How Big Talk works",
            subtitle: "One short session is enough to get a full read on your speaking."
        ) {
            VStack(spacing: 0) {
                ForEach(Array(beats.enumerated()), id: \.offset) { index, beat in
                    LessonPathRow(
                        state: .available,
                        icon: beat.icon,
                        isLeading: true,
                        hasNext: index < beats.count - 1,
                        nextIsLeading: true
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(beat.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(beat.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onboardingReveal(index)
                }
            }
            .padding(.top, 6)
        } footer: {
            OnboardingCTA(title: "Continue", action: onContinue)
        }
    }
}

// MARK: - What's Inside

/// Beat two: the app inventory and the privacy model, which is what
/// the user is actually agreeing to before the questions start.
struct OnboardingWhatsInsideStep: View {
    let counter: String?
    let onContinue: () -> Void

    private let features: [(icon: String, label: String)] = [
        ("text.bubble.fill", "Daily prompts"),
        ("lungs.fill", "Warm-ups"),
        ("target", "Focus drills"),
        ("book.pages.fill", "Read-aloud"),
        ("doc.richtext.fill", "Your own scripts"),
        ("graduationcap.fill", "Guided curriculum"),
        ("heart.fill", "Calm-down tools"),
        ("chart.line.uptrend.xyaxis", "Progress charts"),
        ("flame.fill", "Goals & streaks"),
        ("trophy.fill", "Achievements")
    ]

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "What's inside",
            subtitle: "Ten ways to practice, all built on the same scoring. Everything runs on this iPhone."
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    featureTile(icon: feature.icon, label: feature.label)
                        // Halved so ten tiles finish arriving in about the time
                        // three cards do. A full-speed stagger over a grid
                        // reads as a stutter, not a cascade.
                        .onboardingReveal(index / 2)
                }
            }

            GlassCard(padding: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.success)
                    // iCloud sync turns itself on for signed-in accounts, so
                    // this cannot claim audio never leaves the device, only
                    // that nothing is processed off-device or sent to us.
                    Text("Recording, transcription, and scoring all happen on this iPhone. No Big Talk account, no third-party servers, works in airplane mode. With iCloud sync on, sessions back up to your own private iCloud; turn it off any time in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onboardingReveal(features.count / 2 + 1)
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
            subtitle: "Your name is added to the on-device dictionary so transcripts spell it correctly when you say it out loud."
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
            subtitle: "Pick the closest fit. It shapes the prompts you see on Today and the tips you get after a session."
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingGoal.allCases) { goal in
                    OnboardingChoiceCard(
                        title: goal.displayName,
                        subtitle: goal.subtitle,
                        isSelected: selectedGoal == goal
                    ) {
                        onSelect(goal)
                    }
                }
            }
            .motion(AppMotion.snap, value: selectedGoal)
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
            subtitle: "This sets how hard your daily prompts are and which starter vocabulary we seed."
        ) {
            SectionPicker(
                sections: SpeakerLevel.allCases,
                selection: levelBinding,
                label: { $0.displayName }
            )

            GlassCard(tint: AppColors.glassTintPrimary, padding: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(selected.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

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
    /// Why the last typed word didn't land. `addVocabWord` rejects unknown
    /// spellings and duplicates with an error haptic and nothing else, which
    /// reads as the field eating your word.
    @State private var rejectionNote: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        OnboardingPage(
            counter: counter,
            title: "Words you want to use more",
            subtitle: "Using these in a session lifts your vocabulary score. We've seeded a starter set for your level. Edit it however you like."
        ) {
            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    inputRow

                    if let rejectionNote {
                        Text(rejectionNote)
                            .font(.caption2)
                            .foregroundStyle(AppColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

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
                .motion(AppMotion.snap, value: vocabWords)
                .motion(AppMotion.snap, value: rejectionNote)
            }

            Text("Tap the mic to add words by speaking them. Manage the full word bank later in Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        } footer: {
            OnboardingCTA(title: "Continue") {
                commitPending()
                onContinue()
            }
        }
        .onDisappear {
            // Also covers Back and the top-bar Skip, which never route through
            // the footer.
            commitPending()
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
            .onChange(of: newWord) { rejectionNote = nil }
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
            .symbolEffect(.pulse, isActive: dictationEngine.isListening)
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
            rejectionNote = nil
        } else {
            rejectionNote = "\"\(trimmed)\" wasn't added. Check the spelling, or it's already on the list."
        }
    }

    /// Flush whatever the user typed or dictated but never committed. Leaving
    /// the page used to silently drop a half-entered word and every word still
    /// sitting in an open dictation session.
    private func commitPending() {
        if dictationEngine.isListening { toggleDictation() }
        commitNewWord()
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

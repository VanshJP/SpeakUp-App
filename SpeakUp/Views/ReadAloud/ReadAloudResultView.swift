import SwiftUI

struct ReadAloudResultView: View {
    let result: ReadAloudResult
    let onRetry: () -> Void
    let onDone: () -> Void
    /// Runs a short passage built from this take: the stumbles, or the words
    /// behind one sound to check. Nil hides both practice buttons.
    var onPractice: ((ReadAloudPassage) -> Void)?
    /// Set only when this take was a drill: back to the passage it came from.
    /// Without it a drill was a dead end - Retry repeated the drill and Done
    /// left, so the fix was never checked on the full read.
    var onReadFullPassage: (() -> Void)?

    @State private var selectedWord: WordDetail?
    @State private var pronunciationService = PronunciationService()
    /// The ring sweeps and the number counts up on arrival, like a drill result.
    @State private var counted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var reviewFontSize: CGFloat = 16

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            VStack(spacing: 0) {
                header

                PageScrollView {
                    VStack(spacing: 20) {
                        scoreHero
                            .padding(.top, 8)

                        statsRow

                        if let notice = result.notice {
                            noticeCard(notice)
                        }

                        soundsSection

                        wordReviewSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                // The next rep is always one tap away: these sat under the
                // whole word review, a long scroll on any real passage.
                .safeAreaBar(edge: .bottom) {
                    actions
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
            }
        }
        .sheet(item: $selectedWord) { detail in
            WordDetailSheet(detail: detail, pronunciationService: pronunciationService)
        }
        .task { await reveal() }
    }

    // MARK: - Header

    /// Pinned, so Done is never below the word review. The page used to open
    /// on a title that scrolled up under the status bar and end on three
    /// buttons of three different widths.
    private var header: some View {
        ZStack {
            Text(result.passage.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 88)

            HStack {
                Spacer()
                GlassButton(title: "Done", style: .secondary, size: .small) {
                    Haptics.light()
                    onDone()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Score

    private var verdict: String {
        if result.notice != nil { return "Session ended early" }
        switch result.score {
        case 95...: return "Clean read"
        case 80..<95: return "Nearly there"
        case 60..<80: return "Getting there"
        default: return "Keep at it"
        }
    }

    private var scoreHero: some View {
        VStack(spacing: 14) {
            ZStack {
                RingProgress(
                    progress: counted ? Double(result.score) / 100.0 : 0,
                    color: scoreColor,
                    lineWidth: 12
                )
                .frame(width: 150, height: 150)

                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        CountUpText(
                            value: counted ? Double(result.score) : 0,
                            font: .system(size: 40, weight: .bold, design: .rounded)
                        )
                        Text("%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text("Accuracy")
                        .eyebrowStyle()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Accuracy \(result.score) percent")

            VStack(spacing: 4) {
                Text(verdict)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                if let paceLabel {
                    Text(paceLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// One tile recipe for all three. They used to carry their own tints -
    /// green, red and blue glass - so the same box came in three shades and
    /// the red one read grey.
    private var statsRow: some View {
        HStack(spacing: 10) {
            StatBadge(
                icon: "checkmark.circle.fill",
                value: "\(result.matchedWords)",
                label: "Matched",
                color: AppColors.success
            )
            StatBadge(
                icon: "xmark.circle.fill",
                value: "\(result.mismatchedWords)",
                label: "Missed",
                color: AppColors.error
            )
            StatBadge(
                icon: "clock.fill",
                value: formattedTime,
                label: "Time",
                color: AppColors.info
            )
        }
    }

    private func noticeCard(_ notice: String) -> some View {
        GlassCard(tint: AppColors.warning.opacity(0.06), padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.warning)
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            GlassButton(title: "Try again", icon: "arrow.clockwise", style: .primary, fullWidth: true) {
                Haptics.medium()
                onRetry()
            }

            // A drill's own misses are a near-copy of Try again, so a drill's
            // result offers the step the loop was missing instead.
            if let onReadFullPassage {
                GlassButton(title: "Read full passage", icon: "text.alignleft", style: .secondary, fullWidth: true) {
                    Haptics.medium()
                    onReadFullPassage()
                }
                .accessibilityHint("Reads the whole passage this drill came from")
            } else if let misses = result.missedPhrasesText, onPractice != nil {
                GlassButton(title: "Drill what you missed", icon: "target", style: .secondary, fullWidth: true) {
                    practice(misses)
                }
                .accessibilityHint("Reads only the phrases you missed or skipped")
            }
        }
    }

    private func reveal() async {
        guard !counted else { return }
        guard !reduceMotion else {
            counted = true
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeOut(duration: 0.9)) { counted = true }
        await Haptics.playCountUp(to: result.score, duration: 0.9, cutoff: 0.8)
    }

    // MARK: - Sounds to Check

    /// The consonants behind the misses, grouped by sound. The top three
    /// only: past that, a list stops being a place to start.
    @ViewBuilder
    private var soundsSection: some View {
        let patterns = Array(result.soundCheck.patterns.prefix(3))
        if !patterns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionHeader("Sounds to check")

                Text("Read from the words we heard instead of the ones on the page. Recognition can mishear, so treat these as places to listen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(patterns) { pattern in
                    soundPatternCard(pattern)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func soundPatternCard(_ pattern: SoundPattern) -> some View {
        GlassCard(tint: AppColors.error.opacity(0.06), padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                GlassCardTitle(pattern.title) {
                    Text(pattern.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                WrappingHStack(spacing: 14, lineSpacing: 6) {
                    ForEach(pattern.words, id: \.index) { word in
                        slipWordPair(word)
                    }
                }

                Label {
                    Text(pattern.tip)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(AppColors.warning)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if onPractice != nil, let text = pattern.practiceText {
                    GlassButton(title: "Practice", icon: "target", style: .secondary, size: .small) {
                        practice(text, title: "\(pattern.title) practice")
                    }
                    .accessibilityHint("Reads these words on their own, then in their sentences")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "three → free", the letters that changed marked in the word.
    private func slipWordPair(_ word: SoundSlipWord) -> some View {
        let target = MarkedWordText.make(
            word.bareWord,
            marking: word.bareLetters,
            base: .white,
            mark: AppColors.error
        )
        let arrow = Text(verbatim: "→").foregroundStyle(.tertiary)
        let heard = Text(verbatim: word.bareHeard).foregroundStyle(.secondary)
        return Text("\(target) \(arrow) \(heard)")
            .font(.subheadline)
            .accessibilityLabel("\(word.bareWord), heard as \(word.bareHeard). \(word.slip.summary)")
    }

    /// Runs `text` as a short passage in the same cover.
    private func practice(_ text: String, title: String? = nil) {
        guard let passage = ReadAloudPassage.custom(from: text, title: title) else { return }
        Haptics.medium()
        onPractice?(passage)
    }

    // MARK: - Word Review

    private var wordReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Word review")

            // Wraps rather than squeezing four labels onto one line.
            FlowLayout(spacing: 14) {
                legendItem(color: AppColors.success, label: "Matched")
                legendItem(color: AppColors.error, label: "Said differently")
                legendItem(color: AppColors.warning, label: "Skipped")
                legendItem(color: .white.opacity(0.4), label: "Not reached")
            }
            .font(.caption)

            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .foregroundStyle(AppColors.primary)
                Text("Tap a highlighted word for pronunciation & definition")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            GlassCard(padding: 16) {
                WrappingHStack(spacing: 6, lineSpacing: 10) {
                    ForEach(Array(result.passage.words.enumerated()), id: \.offset) { index, word in
                        let state = index < result.wordStates.count ? result.wordStates[index] : WordMatchState.upcoming
                        reviewWordText(word, index: index, state: state)
                            .font(.system(size: reviewFontSize))
                            .padding(.vertical, 1)
                            .onTapGesture {
                                guard state.isSettled else { return }
                                Haptics.light()
                                selectedWord = WordDetail(word: word, index: index, state: state)
                            }
                            .accessibilityLabel(reviewWordLabel(word, index: index, state: state))
                            .accessibilityAddTraits(state.isSettled ? .isButton : [])
                    }
                }
            }
        }
    }

    /// A miss with a consonant slip marks only that consonant, and the rest
    /// of the word stays red but quieter, so the marked letters lead.
    private func reviewWordText(_ word: String, index: Int, state: WordMatchState) -> Text {
        if let slip = result.soundCheck.slip(at: index) {
            return MarkedWordText.make(
                word,
                marking: slip.letters,
                base: AppColors.error.opacity(0.6),
                mark: AppColors.error
            )
        }
        return Text(word)
            .foregroundStyle(reviewWordColor(for: index))
            .underline(state.isSettled && state.needsAttention)
    }

    /// Same grammar as the live session's labels, so the two surfaces read
    /// alike under VoiceOver, plus the consonant when there is one.
    private func reviewWordLabel(_ word: String, index: Int, state: WordMatchState) -> String {
        switch state {
        case .upcoming, .current:
            return ""
        case .matched:
            return word
        case .mismatched(let spoken):
            guard let slip = result.soundCheck.slip(at: index) else {
                return "missed \(word), you said \(spoken)"
            }
            return "missed \(word), you said \(spoken). \(slip.summary)"
        case .skipped:
            return "\(word), skipped"
        }
    }


    private func reviewWordColor(for index: Int) -> Color {
        guard index < result.wordStates.count else { return .white.opacity(0.4) }
        switch result.wordStates[index] {
        case .matched: return AppColors.success
        case .mismatched: return AppColors.error
        case .skipped: return AppColors.warning
        case .upcoming: return .white.opacity(0.4)
        case .current: return .white.opacity(0.4)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        result.timeTaken.minutesSeconds
    }

    /// Words actually said over reading time. `mismatchedWords` also counts
    /// skips, and a skipped line was never spoken - counting it read as a
    /// reader rushing when they had jumped ahead.
    private var paceLabel: String? {
        guard result.timeTaken > 5 else { return nil }
        let spoken = result.wordStates.filter { $0.isSettled && $0 != .skipped }.count
        let wpm = Double(spoken) / (result.timeTaken / 60)
        return "\(Int(wpm.rounded())) wpm · target ≈150"
    }

    private var scoreColor: Color {
        AppColors.scoreColor(for: result.score)
    }

}

// MARK: - Stat Badge

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard(cornerRadius: 16, padding: 12) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)

                Text(value)
                    .font(.metricValue)
                    .foregroundStyle(.white)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

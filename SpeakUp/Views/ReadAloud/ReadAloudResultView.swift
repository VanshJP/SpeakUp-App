import SwiftUI

struct ReadAloudResultView: View {
    let result: ReadAloudResult
    let onRetry: () -> Void
    let onDone: () -> Void
    /// Runs a short passage built from this take: the stumbles, or the words
    /// behind one sound to check. Nil hides both practice buttons.
    var onPractice: ((ReadAloudPassage) -> Void)?

    @State private var selectedWord: WordDetail?
    @State private var pronunciationService = PronunciationService()

    @ScaledMetric(relativeTo: .body) private var reviewFontSize: CGFloat = 16

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(result.notice == nil ? "Session Complete" : "Session Ended")
                            .font(.title2.bold())

                        Text(result.passage.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    ZStack {
                        RingProgress(
                            progress: Double(result.score) / 100.0,
                            color: scoreColor,
                            lineWidth: 11
                        )
                        .frame(width: 140, height: 140)

                        VStack(spacing: 2) {
                            Text("\(result.score)%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Accuracy")
                                .eyebrowStyle()
                        }
                    }

                    HStack(spacing: 12) {
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

                    if let paceLabel {
                        Text(paceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let notice = result.notice {
                        GlassCard(tint: AppColors.warning.opacity(0.08), padding: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppColors.warning)
                                Text(notice)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    soundsSection

                    wordReviewSection

                    VStack(spacing: 12) {
                        GlassButton(title: "Try again", icon: "arrow.clockwise", style: .primary) {
                            Haptics.medium()
                            onRetry()
                        }

                        if let misses = result.missedPhrasesText, onPractice != nil {
                            GlassButton(title: "Drill what you missed", icon: "target", style: .secondary) {
                                guard let passage = ReadAloudPassage.custom(from: misses) else { return }
                                Haptics.medium()
                                onPractice?(passage)
                            }
                            .accessibilityHint("Reads only the phrases you missed or skipped")
                        }

                        GlassButton(title: "Done", icon: "checkmark", style: .secondary) {
                            Haptics.light()
                            onDone()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $selectedWord) { detail in
            WordDetailSheet(detail: detail, pronunciationService: pronunciationService)
        }
    }

    // MARK: - Sounds to Check

    /// The consonants behind the misses, grouped by sound. The top three
    /// only: past that, a list stops being a place to start.
    @ViewBuilder
    private var soundsSection: some View {
        let patterns = Array(result.soundCheck.patterns.prefix(3))
        if !patterns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sounds to check", systemImage: "mouth")
                    .font(.headline)

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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pattern.title)
                        .font(.headline)
                    Text(pattern.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
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

                if onPractice != nil, pattern.practiceText != nil {
                    GlassButton(title: "Practice", icon: "target", style: .secondary, size: .small) {
                        practice(pattern)
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

    private func practice(_ pattern: SoundPattern) {
        guard let text = pattern.practiceText,
              let passage = ReadAloudPassage.custom(from: text, title: "\(pattern.title) practice")
        else { return }
        Haptics.medium()
        onPractice?(passage)
    }

    // MARK: - Word Review

    private var wordReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Word review", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            HStack(spacing: 16) {
                legendItem(color: AppColors.success, label: "Matched")
                legendItem(color: AppColors.error, label: "Mismatched")
                legendItem(color: AppColors.warning, label: "Skipped")
                legendItem(color: .white.opacity(0.4), label: "Not reached")
            }
            .font(.caption2)

            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .foregroundStyle(AppColors.primary)
                Text("Tap a highlighted word for pronunciation & definition")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            GlassCard {
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

    private var paceLabel: String? {
        guard result.timeTaken > 5 else { return nil }
        let spoken = result.matchedWords + result.mismatchedWords
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
        GlassCard(cornerRadius: 12, tint: color.opacity(0.08), padding: 10) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)

                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

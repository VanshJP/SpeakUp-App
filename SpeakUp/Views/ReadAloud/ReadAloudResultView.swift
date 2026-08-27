import SwiftUI

struct ReadAloudResultView: View {
    let result: ReadAloudResult
    let onRetry: () -> Void
    let onDone: () -> Void

    @State private var selectedWord: WordDetail?
    @State private var pronunciationService = PronunciationService()

    @ScaledMetric(relativeTo: .body) private var reviewFontSize: CGFloat = 16

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(result.notice == nil ? "Session Complete" : "Session Ended")
                            .font(.title2.bold())

                        Text(result.passage.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // Score ring
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
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.8)
                        }
                    }

                    // Stats row
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

                    // Pace closes the loop the passage card opened — it
                    // promised ≈150 wpm, so the result reports what actually
                    // happened. Hidden on very short takes where WPM is noise.
                    if let paceLabel {
                        Text(paceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Degraded-session notice: recognition died mid-read or
                    // nothing was heard. Says so instead of standing as 0%.
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

                    // Word review
                    wordReviewSection

                    // Action buttons
                    VStack(spacing: 12) {
                        GlassButton(title: "Try Again", icon: "arrow.clockwise", style: .primary) {
                            Haptics.medium()
                            onRetry()
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

    // MARK: - Word Review

    private var wordReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Word Review", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            // Legend and hint come first — a reader needs the color key
            // before they scan the wall of words, not after.
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
                WrappingHStack(alignment: .leading, spacing: 6, lineSpacing: 10) {
                    ForEach(Array(result.passage.words.enumerated()), id: \.offset) { index, word in
                        let state = index < result.wordStates.count ? result.wordStates[index] : WordMatchState.upcoming
                        Text(word)
                            .font(.system(size: reviewFontSize))
                            .foregroundStyle(reviewWordColor(for: index))
                            .underline(isWordTappable(state) && isWordHighlighted(state))
                            .padding(.vertical, 1)
                            .onTapGesture {
                                guard isWordTappable(state) else { return }
                                Haptics.light()
                                selectedWord = WordDetail(word: word, index: index, state: state)
                            }
                            .accessibilityLabel(reviewWordLabel(word, state: state))
                    }
                }
            }
        }
    }

    /// Same grammar as the live session's labels, so the two surfaces read
    /// identically under VoiceOver.
    private func reviewWordLabel(_ word: String, state: WordMatchState) -> String {
        switch state {
        case .upcoming, .current:
            return ""
        case .matched:
            return word
        case .mismatched(let spoken):
            return "missed \(word), you said \(spoken)"
        case .skipped:
            return "\(word), skipped"
        }
    }

    private func isWordTappable(_ state: WordMatchState) -> Bool {
        switch state {
        case .matched, .mismatched, .skipped: return true
        case .upcoming, .current: return false
        }
    }

    private func isWordHighlighted(_ state: WordMatchState) -> Bool {
        switch state {
        case .mismatched, .skipped: return true
        default: return false
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

    /// Actual pace against the ≈150 wpm the passage card promised. Needs a
    /// long enough take to mean anything.
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

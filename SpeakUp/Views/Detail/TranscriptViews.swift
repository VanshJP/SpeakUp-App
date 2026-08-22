import SwiftUI

// Extracted from RecordingDetailView. `SpeakerTurn` and its views were
// file-private; they are internal now so the detail view can still build
// turns while the rendering lives here.


struct TranscriptContentView: View {
    let words: [TranscriptionWord]
    let turns: [SpeakerTurn]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool
    let showSpeakerTurns: Bool
    let hasSpeakerSeparation: Bool
    /// Plays from a word's start time. The transcript is the one place where
    /// every moment already has a timestamp attached, which makes it the
    /// natural scrubber — tap the word, hear yourself say it.
    var onPlayFrom: ((TimeInterval) -> Void)?

    var body: some View {
        if showSpeakerTurns && hasSpeakerSeparation {
            SpeakerTurnTranscriptView(
                turns: turns,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights,
                onPlayFrom: onPlayFrom
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            HighlightedTranscriptView(
                words: words,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights,
                onPlayFrom: onPlayFrom
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Highlighted Transcript View

struct HighlightedTranscriptView: View {
    let words: [TranscriptionWord]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool
    var onPlayFrom: ((TimeInterval) -> Void)?

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(words) { word in
                WordView(
                    word: word,
                    showFillerHighlight: showFillerHighlights && word.isFiller,
                    showVocabHighlight: showVocabHighlights && word.isVocabWord,
                    onPlayFrom: onPlayFrom
                )
            }
        }
    }
}

struct SpeakerTurn: Identifiable {
    let id: Int
    let isPrimarySpeaker: Bool
    let words: [TranscriptionWord]
}

struct SpeakerTurnTranscriptView: View {
    let turns: [SpeakerTurn]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool
    var onPlayFrom: ((TimeInterval) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(turns) { turn in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: turn.isPrimarySpeaker ? "person.fill.checkmark" : "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(turn.isPrimarySpeaker ? AppColors.primary : .secondary)

                        Text(turn.isPrimarySpeaker ? "You" : "Other speaker")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(turn.isPrimarySpeaker ? AppColors.primary : .secondary)
                    }

                    HighlightedTranscriptView(
                        words: turn.words,
                        showFillerHighlights: showFillerHighlights,
                        showVocabHighlights: showVocabHighlights,
                        onPlayFrom: onPlayFrom
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(turn.isPrimarySpeaker ? AppColors.primary.opacity(0.12) : .white.opacity(0.05))
                )
            }
        }
    }
}

struct WordView: View {
    let word: TranscriptionWord
    let showFillerHighlight: Bool
    let showVocabHighlight: Bool
    var onPlayFrom: ((TimeInterval) -> Void)?

    private var isHighlighted: Bool { showFillerHighlight || showVocabHighlight }

    /// Tuned tones, not `.orange`/`.green` — the system colors are pitched for
    /// light UI and go muddy over the navy canvas.
    private var highlightColor: Color {
        showFillerHighlight ? AppColors.warning : AppColors.success
    }

    private var foreground: Color {
        isHighlighted ? highlightColor : .primary
    }

    var body: some View {
        // The gesture is attached only when there is somewhere to play from.
        // An unconditional `onTapGesture` would still swallow the tap when the
        // handler is nil, which breaks the excerpt card's own tap-to-open.
        // Unusable timestamps are the second gate: Whisper's alignment heads
        // emit zero (or non-finite) starts often enough that tapping such a
        // word jumped to the top of the take instead of the word itself.
        if let onPlayFrom, hasPlayableTimestamp {
            label
                // A word is a small target, so the hit area is widened rather
                // than the glyph. Inset matches half the layout spacing so
                // neighbours meet without overlapping and stealing taps. No
                // button chrome: 300 buttons would read as a form, not prose.
                .contentShape(.rect.inset(by: -2))
                .onTapGesture { onPlayFrom(word.start) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Plays from this word")
        } else {
            label
        }
    }

    /// A start of exactly zero is only trustworthy for the first word of a
    /// take; anywhere else it is a dropped alignment stamp. The drawer's play
    /// button still covers "from the top", so no gesture is the safe default.
    private var hasPlayableTimestamp: Bool {
        word.start.isFinite && word.start > 0
    }

    private var label: some View {
        Text(word.word)
            .font(.body)
            .foregroundStyle(foreground)
            .padding(.horizontal, isHighlighted ? 4 : 0)
            .padding(.vertical, isHighlighted ? 2 : 0)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(highlightColor.opacity(0.2))
                }
            }
    }
}

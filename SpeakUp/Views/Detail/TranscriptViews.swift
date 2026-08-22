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

    var body: some View {
        if showSpeakerTurns && hasSpeakerSeparation {
            SpeakerTurnTranscriptView(
                turns: turns,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            HighlightedTranscriptView(
                words: words,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights
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

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(words) { word in
                WordView(
                    word: word,
                    showFillerHighlight: showFillerHighlights && word.isFiller,
                    showVocabHighlight: showVocabHighlights && word.isVocabWord
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
                        showVocabHighlights: showVocabHighlights
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
        // Plain prose — no tap gesture. Tapping the transcript used to start
        // playback from the tapped word, which read as the recording playing
        // itself whenever someone just wanted to read or select text.
        // Playback starts only from explicit controls: the drawer's play
        // button, the waveform scrubber, and the play-chips on fillers,
        // swaps, and coach tips.
        label
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

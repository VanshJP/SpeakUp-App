import SwiftUI


struct TranscriptContentView: View {
    let words: [TranscriptionWord]
    let turns: [SpeakerTurn]
    let showFillerHighlights: Bool
    let showVocabHighlights: Bool
    let showSpeakerTurns: Bool
    let hasSpeakerSeparation: Bool
    var structuralWordIDs: Set<UUID> = []
    var onPlayWord: ((TranscriptionWord) -> Void)? = nil

    var body: some View {
        if showSpeakerTurns && hasSpeakerSeparation {
            SpeakerTurnTranscriptView(
                turns: turns,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights,
                structuralWordIDs: structuralWordIDs,
                onPlayWord: onPlayWord
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            HighlightedTranscriptView(
                words: words,
                showFillerHighlights: showFillerHighlights,
                showVocabHighlights: showVocabHighlights,
                structuralWordIDs: structuralWordIDs,
                onPlayWord: onPlayWord
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
    var structuralWordIDs: Set<UUID> = []
    var onPlayWord: ((TranscriptionWord) -> Void)? = nil

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(words) { word in
                WordView(
                    word: word,
                    showFillerHighlight: showFillerHighlights && word.isFiller,
                    showVocabHighlight: showVocabHighlights && word.isVocabWord,
                    showStructuralHighlight: structuralWordIDs.contains(word.id),
                    onPlay: onPlayWord.map { callback in { callback(word) } }
                )
            }
        }
        // One element, read as prose. Every word used to be its own stop, so
        // VoiceOver crawled a take a word at a time; the tappable openings
        // stay reachable as actions on the passage.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.map(\.word).joined(separator: " "))
        .accessibilityValue(fillerSummary)
        .accessibilityActions {
            if let onPlayWord {
                ForEach(playableOpenings) { word in
                    Button("Play repeated opening, \(word.word)") { onPlayWord(word) }
                }
            }
        }
    }

    /// Same rule `WordView` uses for its button (recording-detail invariant 18).
    private var playableOpenings: [TranscriptionWord] {
        words.filter { structuralWordIDs.contains($0.id) && $0.start > 0 && $0.start.isFinite }
    }

    private var fillerSummary: String {
        guard showFillerHighlights else { return "" }
        let count = words.reduce(0) { $0 + ($1.isFiller ? 1 : 0) }
        switch count {
        case 0: return ""
        case 1: return "1 filler word highlighted"
        default: return "\(count) filler words highlighted"
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
    var structuralWordIDs: Set<UUID> = []
    var onPlayWord: ((TranscriptionWord) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(turns) { turn in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: turn.isPrimarySpeaker ? "person.fill.checkmark" : "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(turn.isPrimarySpeaker ? AppColors.primary : .secondary)
                            .accessibilityHidden(true)

                        Text(turn.isPrimarySpeaker ? "You" : "Other speaker")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(turn.isPrimarySpeaker ? AppColors.primary : .secondary)
                    }

                    HighlightedTranscriptView(
                        words: turn.words,
                        showFillerHighlights: showFillerHighlights,
                        showVocabHighlights: showVocabHighlights,
                        structuralWordIDs: structuralWordIDs,
                        onPlayWord: onPlayWord
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
    var showStructuralHighlight: Bool = false
    /// Only structural openings are tappable - whole-transcript tap was removed
    /// because it felt like the recording playing itself while reading.
    var onPlay: (() -> Void)? = nil

    private var isHighlighted: Bool {
        showFillerHighlight || showVocabHighlight || showStructuralHighlight
    }

    /// Tuned tones, not `.orange`/`.green` - the system colors are pitched for
    /// light UI and go muddy over the navy canvas. Structural frames use plum
    /// so they never read as hesitation fillers.
    private var highlightColor: Color {
        if showFillerHighlight { return AppColors.warning }
        if showStructuralHighlight { return AppColors.categoryPlum }
        return AppColors.success
    }

    private var foreground: Color {
        isHighlighted ? highlightColor : .primary
    }

    var body: some View {
        if showStructuralHighlight, let onPlay, word.start > 0, word.start.isFinite {
            Button(action: onPlay) {
                label
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Play repeated opening, \(word.word)")
        } else {
            label
        }
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

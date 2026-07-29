import SwiftUI

/// The stretch of speech where the fillers actually clustered, shown in the
/// Breakdown tab next to the numbers that summarize it.
///
/// "12 fillers" is a fact you can't act on. Seeing *"so I um think that, uh,
/// the main thing is"* is — the feedback attaches to the words that caused it,
/// which is the one thing a transcript can do that a metric can't. The full
/// transcript is a tab away; this is the part worth reading.
///
/// Renders nothing when there were no fillers. A clean take shouldn't be handed
/// an empty card congratulating itself.
struct TranscriptExcerptCard: View {
    let words: [TranscriptionWord]
    let onOpenTranscript: () -> Void

    /// Wide enough to carry sentence context, short enough to stay scannable.
    private static let windowSize = 26

    var body: some View {
        if let window = densestFillerWindow {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    header(fillerCount: window.fillerCount)

                    HighlightedTranscriptView(
                        words: window.words,
                        showFillerHighlights: true,
                        showVocabHighlights: false
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Text("See full transcript")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.light()
                onOpenTranscript()
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the full transcript")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func header(fillerCount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "text.quote")
                .font(.caption2.weight(.semibold))
            Text(fillerCount == 1 ? "Where a filler landed" : "Where the fillers clustered")
            Spacer()
        }
        .eyebrowStyle()
    }

    // MARK: - Excerpt selection

    private struct Window {
        let words: [TranscriptionWord]
        let fillerCount: Int
    }

    /// Slides a fixed window across the transcript and keeps the densest one.
    /// Ties resolve to the earliest window — the first stumble is the one the
    /// speaker is most likely to remember.
    private var densestFillerWindow: Window? {
        guard words.contains(where: \.isFiller) else { return nil }

        guard words.count > Self.windowSize else {
            return Window(words: words, fillerCount: fillerCount(in: words))
        }

        var bestStart = 0
        var bestCount = -1

        for start in 0...(words.count - Self.windowSize) {
            let count = fillerCount(in: words[start ..< start + Self.windowSize])
            if count > bestCount {
                bestCount = count
                bestStart = start
            }
        }

        return Window(
            words: Array(words[bestStart ..< bestStart + Self.windowSize]),
            fillerCount: bestCount
        )
    }

    private func fillerCount<C: Collection>(in words: C) -> Int
    where C.Element == TranscriptionWord {
        words.reduce(0) { $0 + ($1.isFiller ? 1 : 0) }
    }
}

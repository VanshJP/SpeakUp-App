import SwiftUI

struct TranscriptExcerptCard: View {
    let words: [TranscriptionWord]
    let onOpenTranscript: () -> Void

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

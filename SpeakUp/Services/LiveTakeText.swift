import Foundation

/// One word in the live caption running above the recording timer.
nonisolated struct LiveCaptionToken: Equatable, Sendable, Hashable {
    let text: String
    let isFiller: Bool
}

/// Caption slicing and hesitation highlighting for the live take.
///
/// Filler *counting* still goes through `FillerDetectionPipeline` (pause and
/// context aware). The caption only paints unambiguous hesitations so "like"
/// in "I like this" never lights up amber mid-sentence.
nonisolated enum LiveTakeText {
    static let captionWordLimit = 14

    static let hesitations: Set<String> = [
        "um", "uh", "er", "ah", "hmm", "hm", "uhh", "umm"
    ]

    static func normalizedWord(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }

    /// Spotlight words in `text` that are not already matched, as lowercase keys.
    ///
    /// Empty return means "nothing changed", which is what lets the caller skip
    /// the `@Observable` write and leave the chip strip alone. Inflection comes
    /// from `VocabMatcher`, the same matcher post-take analysis uses, so a chip
    /// lighting up mid-take always agrees with the score afterwards.
    static func newlyHeard(targets: [String], in text: String, already: Set<String>) -> Set<String> {
        guard !targets.isEmpty, !text.isEmpty else { return [] }
        var found: Set<String> = []
        for word in targets where !already.contains(word.lowercased()) {
            if VocabMatcher.contains(word, in: text) {
                found.insert(word.lowercased())
            }
        }
        return found
    }

    static func tokens(words: [String], limit: Int = captionWordLimit) -> [LiveCaptionToken] {
        words.suffix(limit).map { word in
            LiveCaptionToken(
                text: word,
                isFiller: hesitations.contains(normalizedWord(word))
            )
        }
    }
}

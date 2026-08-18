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

    static func tokens(words: [String], limit: Int = captionWordLimit) -> [LiveCaptionToken] {
        words.suffix(limit).map { word in
            LiveCaptionToken(
                text: word,
                isFiller: hesitations.contains(normalizedWord(word))
            )
        }
    }
}

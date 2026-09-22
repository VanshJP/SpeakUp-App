import Foundation

// MARK: - Recognition Continuity

/// How a new result from a live `SFSpeechRecognitionTask` relates to the
/// transcript already held for the same request.
///
/// SFSpeech does not always report a request as one growing transcript. On
/// device, after a pause of a second or two, it can start the transcript over
/// from empty - same request, `isFinal` still false - and its final result is
/// sometimes blank. Developers have reported this from iOS 17 through iOS 26
/// with `requiresOnDeviceRecognition`, which every recognizer here must set
/// (gotcha §9). Anything that treats the newest result as the whole request
/// loses what came before the pause: Read Aloud snapped the reader back toward
/// the first word, and drills stopped counting the words and fillers spoken
/// after it.
///
/// Pure and `nonisolated` so both consumers - `ReadAloudService` and
/// `LiveTranscriptionService` - share one set of rules, and so tests can pin
/// them without a recognizer.
nonisolated enum RecognitionContinuity: Equatable, Sendable {
    /// The same utterance, grown or revised. Replace what is held.
    case revision
    /// The recognizer moved on to a new utterance. Keep what is held and
    /// start another.
    case restart
    /// A blank or shrunken copy of what is already held. Drop it.
    case ignore

    /// Revisions settle the last word or two as more audio arrives. A result
    /// that loses more than this many words is not a revision.
    static let revisionSlack = 2

    /// Classifies `next` against the utterance currently held.
    ///
    /// - Parameters:
    ///   - previous: The held utterance, from `words(in:)`.
    ///   - next: The new result, from `words(in:)`.
    ///   - previousClosed: The recognizer marked the held utterance finished
    ///     (a result carrying `speechRecognitionMetadata`). Whatever follows is
    ///     new speech unless it repeats or continues that utterance.
    static func classify(previous: [String], next: [String], previousClosed: Bool) -> RecognitionContinuity {
        guard !previous.isEmpty else { return .revision }
        guard !next.isEmpty else { return .ignore }

        let prefix = commonPrefixLength(previous, next)

        if previousClosed {
            // A recognizer that does keep the whole request in one transcript
            // repeats the finished utterance at the front of its next result.
            if prefix == previous.count, next.count > previous.count { return .revision }
            // The finished utterance reported again, its last word perhaps
            // settled differently.
            if previous.count > 1, next.count == previous.count, prefix >= previous.count - 1 {
                return .revision
            }
            return isContiguousRun(next, in: previous) ? .ignore : .restart
        }

        // Growth, or the tail revised as more audio arrived.
        if prefix >= previous.count - revisionSlack, next.count >= previous.count - 1 {
            return .revision
        }

        // Lost more words than a revision does: a blank-ish final, a final
        // that kept only its last utterance, or the first words of a new one.
        if next.count + revisionSlack < previous.count {
            return isContiguousRun(next, in: previous) ? .ignore : .restart
        }

        // About the same length but diverging early. A rewrite keeps most of
        // the held words in order; new speech keeps almost none of them.
        return sharedWordCount(previous, next) * 2 >= previous.count ? .revision : .restart
    }

    // MARK: - Comparison form

    /// Lowercased words with edge punctuation removed. Recognizers
    /// re-punctuate and re-capitalise a result as it settles, and neither
    /// makes it different speech.
    static func words(in transcript: String) -> [String] {
        transcript
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.lowercased()
                    .replacingOccurrences(of: "’", with: "'")
                    .trimmingCharacters(in: .punctuationCharacters)
            }
            .filter { !$0.isEmpty }
    }

    static func commonPrefixLength(_ a: [String], _ b: [String]) -> Int {
        var length = 0
        while length < a.count, length < b.count, a[length] == b[length] {
            length += 1
        }
        return length
    }

    /// Whether `needle` appears in `haystack` as consecutive words.
    static func isContiguousRun(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return true
        }
        return false
    }

    /// Words the two lists share in order: their common prefix plus the
    /// longest common subsequence of what follows it, over at most `window`
    /// words of each. Enough to tell a rewrite from new speech without going
    /// quadratic over a long take.
    static func sharedWordCount(_ a: [String], _ b: [String], window: Int = 64) -> Int {
        let prefix = commonPrefixLength(a, b)
        let tailA = Array(a[prefix...].prefix(window))
        let tailB = Array(b[prefix...].prefix(window))
        guard !tailA.isEmpty, !tailB.isEmpty else { return prefix }

        var previousRow = [Int](repeating: 0, count: tailB.count + 1)
        var currentRow = previousRow
        for wordA in tailA {
            for (index, wordB) in tailB.enumerated() {
                currentRow[index + 1] = wordA == wordB
                    ? previousRow[index] + 1
                    : max(previousRow[index + 1], currentRow[index])
            }
            swap(&previousRow, &currentRow)
        }
        return prefix + previousRow[tailB.count]
    }
}

// MARK: - Request Transcript

/// What one recognition request has heard, kept as the utterances the
/// recognizer has already moved past plus the one it is still revising.
///
/// Feeding every result through `apply` is what makes an in-request restart
/// harmless: the utterance before the pause is committed rather than
/// overwritten by the one after it, and a blank final cannot erase either.
nonisolated struct RequestTranscript: Equatable, Sendable {
    private(set) var committed: [String] = []
    private(set) var live = ""
    /// The recognizer marked `live` finished. See `RecognitionContinuity`.
    private(set) var liveIsClosed = false

    init() {}

    /// - Parameter utteranceEnded: The result carried
    ///   `speechRecognitionMetadata`, which the recognizer attaches when it
    ///   considers an utterance over - on every final, and on some systems at
    ///   each pause.
    mutating func apply(_ transcript: String, utteranceEnded: Bool) {
        let held = RecognitionContinuity.words(in: live)
        let incoming = RecognitionContinuity.words(in: transcript)

        switch RecognitionContinuity.classify(previous: held, next: incoming, previousClosed: liveIsClosed) {
        case .revision:
            // A finished utterance reported again stays finished; one that
            // grew means the recognizer carried on inside it.
            let grew = incoming.count > held.count
            liveIsClosed = utteranceEnded || (liveIsClosed && !grew)
            live = transcript
        case .restart:
            committed.append(live)
            live = transcript
            liveIsClosed = utteranceEnded
        case .ignore:
            liveIsClosed = liveIsClosed || utteranceEnded
        }
    }

    /// The request's whole transcript, oldest utterance first.
    var text: String {
        ReadAloudService.joinTranscripts(committed + [live])
    }
}

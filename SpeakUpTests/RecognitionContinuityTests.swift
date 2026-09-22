import Foundation
import Testing
@testable import SpeakUp

/// SFSpeech on device can start a request's transcript over after a pause of
/// a second or two - same request, `isFinal` still false - and can deliver a
/// blank final. Read Aloud used to store each request's newest transcript
/// as-is, so a reader who paused between sentences was snapped back toward the
/// first word, and the words after the pause were scored against the top of
/// the passage. These pin the rules that keep every utterance.
struct RecognitionContinuityTests {

    private func words(_ text: String) -> [String] {
        RecognitionContinuity.words(in: text)
    }

    private func classify(_ previous: String, _ next: String, closed: Bool = false) -> RecognitionContinuity {
        RecognitionContinuity.classify(previous: words(previous), next: words(next), previousClosed: closed)
    }

    // MARK: - Comparison form

    @Test func comparisonFormFoldsCaseAndEdgePunctuation() {
        #expect(words("The quick, brown FOX.") == ["the", "quick", "brown", "fox"])
        #expect(words("  Don’t   stop  ") == ["don't", "stop"])
        #expect(words(" , . ") == [])
    }

    // MARK: - Revisions

    @Test func growthAndTailRevisionsReplaceTheUtterance() {
        #expect(classify("", "the") == .revision)
        #expect(classify("the quick", "the quick brown") == .revision)
        #expect(classify("the quick brown fox", "the quick brown box jumps") == .revision)
        #expect(classify("The quick brown fox", "the quick brown fox.") == .revision)
    }

    @Test func rewritesThatKeepMostWordsAreRevisions() {
        // Word merges and splits move the count by one; the words survive.
        #expect(classify("a new york city", "new york city") == .revision)
        #expect(classify("we went to the store", "we want to the store") == .revision)
        // Short utterances are revised constantly and whole.
        #expect(classify("I scream", "ice cream") == .revision)
    }

    // MARK: - Restarts

    @Test func newSpeechAfterAPauseIsARestartNotARevision() {
        #expect(classify("the quick brown fox jumps", "over") == .restart)
        #expect(classify("the quick brown fox jumps", "over the lazy") == .restart)
        #expect(classify("stop right there", "look") == .restart)
        #expect(classify("we went to the store", "and bought some milk and eggs") == .restart)
    }

    @Test func aClosedUtteranceIsFollowedByNewSpeech() {
        #expect(classify("stop", "look", closed: true) == .restart)
        #expect(classify("how are you", "fine", closed: true) == .restart)
    }

    @Test func aCumulativeRecognizerContinuesAClosedUtterance() {
        #expect(classify("how are you", "how are you fine", closed: true) == .revision)
        // The finished utterance reported again.
        #expect(classify("how are you", "How are you?", closed: true) == .revision)
    }

    // MARK: - Ignored

    @Test func blankAndShrunkenResultsNeverTakeWordsBack() {
        #expect(classify("the quick brown fox", "") == .ignore)
        // A final that kept only its last utterance.
        #expect(classify("the quick brown fox jumps over the lazy dog", "over the lazy dog") == .ignore)
        // The first word of a restart that happens to repeat an earlier one
        // waits for the next partial rather than wiping the utterance.
        #expect(classify("the quick brown fox jumps", "the") == .ignore)
        #expect(classify("how are you", "you", closed: true) == .ignore)
    }

    // MARK: - Helpers

    @Test func contiguousRunAndSharedWordCount() {
        #expect(RecognitionContinuity.isContiguousRun(["b", "c"], in: ["a", "b", "c"]))
        #expect(!RecognitionContinuity.isContiguousRun(["a", "c"], in: ["a", "b", "c"]))
        #expect(!RecognitionContinuity.isContiguousRun(["a", "b", "c", "d"], in: ["a", "b", "c"]))
        #expect(RecognitionContinuity.sharedWordCount(["a", "b", "c", "d"], ["a", "x", "c", "d"]) == 3)
        #expect(RecognitionContinuity.sharedWordCount(["a", "b"], ["c", "d"]) == 0)
    }

    // MARK: - Request transcript

    @Test func aRestartInsideARequestKeepsTheUtteranceBeforeIt() {
        var transcript = RequestTranscript()
        for partial in ["The", "The quick", "The quick brown fox"] {
            transcript.apply(partial, utteranceEnded: false)
        }
        // Pause. The recognizer starts over from empty inside the same request.
        for partial in ["jumps", "jumps over", "jumps over the lazy dog"] {
            transcript.apply(partial, utteranceEnded: false)
        }

        #expect(transcript.text == "The quick brown fox jumps over the lazy dog")
    }

    @Test func theUtteranceEndingSignalKeepsEvenOneWordUtterances() {
        var transcript = RequestTranscript()
        transcript.apply("Stop.", utteranceEnded: true)
        transcript.apply("Look", utteranceEnded: false)
        transcript.apply("Look both ways.", utteranceEnded: true)
        transcript.apply("Then", utteranceEnded: false)

        #expect(transcript.text == "Stop. Look both ways. Then")
    }

    @Test func aBlankFinalDoesNotEraseTheRequest() {
        var transcript = RequestTranscript()
        transcript.apply("The quick brown fox", utteranceEnded: false)
        transcript.apply("", utteranceEnded: true)

        #expect(transcript.text == "The quick brown fox")
    }

    @Test func aDuplicateCallbackAtThePauseIsNotCountedTwice() {
        var transcript = RequestTranscript()
        transcript.apply("how are you", utteranceEnded: true)
        transcript.apply("how are you", utteranceEnded: false)
        transcript.apply("fine", utteranceEnded: false)

        #expect(transcript.text == "how are you fine")
    }

    @Test func aCumulativeRecognizerIsNotDoubleCounted() {
        var transcript = RequestTranscript()
        transcript.apply("how are you", utteranceEnded: true)
        transcript.apply("how are you fine", utteranceEnded: false)
        transcript.apply("how are you fine thanks", utteranceEnded: true)

        #expect(transcript.text == "how are you fine thanks")
    }

    // MARK: - End to end with alignment

    /// The shape of the reported bug: three sentences, a pause after each, and
    /// a recognizer that starts its transcript over at every pause. The cursor
    /// must only ever move forward, and every word must match.
    @Test func aReadWithPausesNeverSnapsBackToTheTop() {
        let sentences = [
            "The morning train pulled into the station at seven.",
            "Commuters stepped onto the platform and hurried toward the stairs.",
            "Nobody noticed the violinist playing in the corner."
        ]
        let reference = sentences.joined(separator: " ")
            .components(separatedBy: " ")
        let normalized = reference.map(ReadAloudService.normalize)

        var transcript = RequestTranscript()
        var furthest = 0
        for sentence in sentences {
            let spoken = sentence.components(separatedBy: " ")
            for count in 1...spoken.count {
                transcript.apply(spoken.prefix(count).joined(separator: " "), utteranceEnded: false)

                let heard = transcript.text
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                let progress = ReadAloudService.computeAlignment(
                    reference: reference,
                    normalizedReference: normalized,
                    spokenWords: heard
                ).refIndex
                #expect(progress >= furthest, "cursor moved back from \(furthest) to \(progress)")
                furthest = max(furthest, progress)
            }
        }

        let finished = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: normalized,
            spokenWords: transcript.text.components(separatedBy: " ")
        )
        #expect(finished.refIndex == reference.count)
        #expect(finished.matched == reference.count)
        #expect(finished.mismatched == 0)
    }
}

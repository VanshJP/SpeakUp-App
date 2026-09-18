import Testing
@testable import SpeakUp

struct ReadAloudAlignmentTests {

    // MARK: - Matching basics

    @Test func exactSequenceMatchesEveryWord() {
        let reference = ["The", "quick", "brown", "fox"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["The", "quick", "brown", "fox"]
        )

        #expect(result.matched == 4)
        #expect(result.mismatched == 0)
        #expect(result.refIndex == 4)
        #expect(result.states.allSatisfy { $0 == .matched })
    }

    @Test func punctuationCaseAndApostrophesFoldAway() {
        #expect(ReadAloudService.normalize("Don’t,") == "dont")
        #expect(ReadAloudService.normalize("DON'T") == "dont")
        #expect(ReadAloudService.normalize("Hello") == "hello")
    }

    @Test func emptySpeechLeavesPassageUpcomingWithFirstCurrent() {
        let reference = ["One", "two", "three"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: []
        )

        #expect(result.matched == 0)
        #expect(result.refIndex == 0)
        #expect(result.states.first == .current)
        #expect(result.states.dropFirst().allSatisfy { $0 == .upcoming })
    }

    // MARK: - Skipped words

    @Test func droppedReferenceWordIsMarkedSkipped() {
        let reference = ["the", "cat", "sat"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["cat"]
        )

        #expect(result.states[0] == .skipped)
        #expect(result.states[1] == .matched)
        #expect(result.mismatched == 1)
    }

    // MARK: - Inserted words

    @Test func fillerBetweenMatchesDoesNotConsumeReferenceWord() {
        let reference = ["the", "cat", "sat"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["the", "um", "cat", "sat"]
        )

        #expect(result.matched == 3)
        #expect(result.mismatched == 0)
        #expect(result.states.allSatisfy { $0 == .matched })
    }

    @Test func fillerBeforeSkippedWordStillResyncs() {
        let reference = ["the", "cat", "sat", "down"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["well", "sat", "down"]
        )

        #expect(result.states[0] == .skipped)
        #expect(result.states[1] == .skipped)
        #expect(result.states[2] == .matched)
        #expect(result.states[3] == .matched)
        #expect(result.matched == 2)
    }

    @Test func substitutionWithoutResolvingSuccessorCountsAsMismatch() {
        let reference = ["the", "cat"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["zebra"]
        )

        guard case .mismatched(let spoken) = result.states[0] else {
            Issue.record("Expected mismatch at index 0, got \(result.states[0])")
            return
        }
        #expect(spoken == "zebra")
    }

    @Test func substitutionBeforeResolvableWordIsForgivenAsInsertion() {
        let reference = ["the", "cat"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["zebra", "cat"]
        )

        #expect(result.states[0] == .skipped)
        #expect(result.states[1] == .matched)
        #expect(result.matched == 1)
    }

    // MARK: - Number normalization

    @Test func spelledHyphenatedNumbersMatchDigits() {
        #expect(ReadAloudService.normalize("seventy-two") == "72")
        #expect(ReadAloudService.normalize("Seventy-Two,") == "72")
        #expect(ReadAloudService.normalize("thirty-three") == "33")

        let reference = ["seventy-two", "years"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["72", "years"]
        )
        #expect(result.matched == 2)
    }

    @Test func compoundNumberWordsCollapseToDigits() {
        #expect(ReadAloudService.normalize("one hundred") == "100")
        #expect(ReadAloudService.normalize("onehundredandfive") == "105")
        #expect(ReadAloudService.normalize("twenty") == "20")
    }

    @Test func digitsAndNonNumbersPassThroughUntouched() {
        #expect(ReadAloudService.normalize("72") == "72")
        #expect(ReadAloudService.normalize("elephant") == "elephant")
        #expect(ReadAloudService.normalize("") == "")
    }

    // MARK: - Recognition request boundaries

    /// SFSpeech closes a request after a pause in speech and again at its own
    /// audio-duration ceiling, both of which a reader triggers several times in
    /// one passage. The service re-arms instead of ending the session, and
    /// stitches the requests' transcripts back together - these pin that the
    /// stitching is lossless.

    @Test func joinedSegmentsDropEmptiesAndSingleSpaceTheRest() {
        #expect(ReadAloudService.joinTranscripts(["the quick", "brown fox"]) == "the quick brown fox")
        #expect(ReadAloudService.joinTranscripts(["the quick", ""]) == "the quick")
        #expect(ReadAloudService.joinTranscripts(["", "brown fox"]) == "brown fox")
        #expect(ReadAloudService.joinTranscripts(["  the quick ", " brown fox"]) == "the quick brown fox")
        #expect(ReadAloudService.joinTranscripts(["", "   ", ""]) == "")
        #expect(ReadAloudService.joinTranscripts([]) == "")
    }

    @Test func aReadSplitAcrossRequestsScoresLikeOneContinuousRead() {
        let reference = ["The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]
        let normalized = reference.map(ReadAloudService.normalize)

        let continuous = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: normalized,
            spokenWords: reference
        )

        // Same words, cut into three requests the way a reader's pauses would.
        let segments = ["The quick brown", "fox jumps over", "the lazy dog"]
        let stitched = ReadAloudService.joinTranscripts(segments)
            .components(separatedBy: " ")
        let rearmed = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: normalized,
            spokenWords: stitched
        )

        #expect(rearmed.matched == continuous.matched)
        #expect(rearmed.mismatched == continuous.mismatched)
        #expect(rearmed.refIndex == continuous.refIndex)
        #expect(rearmed.states == continuous.states)
    }

    @Test func openingANewRequestDoesNotRewindTheReader() {
        let reference = ["The", "quick", "brown", "fox", "jumps"]
        let normalized = reference.map(ReadAloudService.normalize)

        func progress(_ segments: [String]) -> Int {
            let words = ReadAloudService.joinTranscripts(segments)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return ReadAloudService.computeAlignment(
                reference: reference,
                normalizedReference: normalized,
                spokenWords: words
            ).refIndex
        }

        // Three words in, the recognizer closes the request and a fresh one
        // opens empty. Without the committed prefix this is where the passage
        // used to snap back to word one.
        let beforeRearm = progress(["The quick brown"])
        let atRearm = progress(["The quick brown", ""])
        let afterRearm = progress(["The quick brown", "fox jumps"])

        #expect(beforeRearm == 3)
        #expect(atRearm == beforeRearm)
        #expect(afterRearm == 5)
    }
}

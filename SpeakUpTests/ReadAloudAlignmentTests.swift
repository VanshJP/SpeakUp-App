import Testing
@testable import SpeakUp

/// Pins the read-aloud alignment engine: greedy matching against a reference
/// passage, including the two ways real reading drifts from the page —
/// skipped words and inserted fillers — plus number normalization, because
/// the page says "seventy-two" while the recognizer writes "72".
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
        // "well" is an insertion whose successor resolves two references
        // ahead; it must drop without eating the skipped word.
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
        // "zebra" before a resolving successor reads as an insertion (see
        // fillerBeforeSkippedWordStillResyncs); only when nothing after it
        // resolves is it scored as a genuine miss.
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

        // The stumble re-syncs on the next word; "the" reads as skipped, not
        // double-penalized.
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
}

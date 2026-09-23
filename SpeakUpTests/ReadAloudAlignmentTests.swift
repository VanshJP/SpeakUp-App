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

    /// A word said in place of the page's, followed by the next page word, is
    /// that word replaced - not a filler plus a skip. The skip reading threw
    /// away what was heard, which is all Sounds to check has to work with.
    @Test func aReplacedWordKeepsWhatWasHeard() {
        let reference = ["the", "cat"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["zebra", "cat"]
        )

        #expect(result.states == [.mismatched(spoken: "zebra"), .matched])
        #expect(result.matched == 1)
        #expect(result.mismatched == 1)
    }

    @Test func aHesitationWhereAWordShouldBeIsStillASkip() {
        let reference = ["the", "cat", "sat"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["um", "cat", "sat"]
        )

        #expect(result.states == [.skipped, .matched, .matched])
        #expect(result.matched == 2)
    }

    /// Read cleanly, "red lorry, yellow lorry" came back with half its lorries
    /// spelled as the name. Same sounds, so they count.
    @Test func aNameTheRecognizerPreferredCountsAsTheWord() {
        let reference = ["Red", "lorry", "yellow", "lorry."]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["red", "Laurie", "yellow", "lorry"]
        )

        #expect(result.states.allSatisfy { $0 == .matched })
        #expect(result.matched == 4)
    }

    @Test func aLowercaseSoundAlikeIsStillAMiss() {
        let reference = ["the", "matter", "is"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["the", "motor", "is"]
        )

        #expect(result.states[1] == .mismatched(spoken: "motor"))
    }

    // MARK: - Words said wrong

    /// "Free" for "three" followed by a clean word used to read as a filler
    /// plus a skip, which threw away what was heard - the part the result
    /// screen needs to point at the consonant. "three" also normalizes to
    /// "3", so the near miss has to be measured on the spelling.
    @Test func aNearMissBeforeACleanWordKeepsWhatWasHeard() {
        let reference = ["three", "people", "came"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["free", "people", "came"]
        )

        #expect(result.states == [.mismatched(spoken: "free"), .matched, .matched])
        #expect(result.matched == 2)
        #expect(result.mismatched == 1)
    }

    /// Minimal pairs put the look-alike right after the word, so a slip
    /// matched ahead and the pack reported every slip as a skip.
    @Test func aMinimalPairSaidWrongIsAMissNotASkip() {
        let reference = ["Thin.", "Tin.", "Thin.", "Tin."]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["tin", "tin", "tin", "tin"]
        )

        #expect(result.states == [.mismatched(spoken: "tin"), .matched, .mismatched(spoken: "tin"), .matched])
        #expect(result.matched == 2)
        #expect(result.mismatched == 2)
    }

    @Test func aSkippedLookAlikeStaysSkipped() {
        let reference = ["tin", "thin", "man"]
        let result = ReadAloudService.computeAlignment(
            reference: reference,
            normalizedReference: reference.map(ReadAloudService.normalize),
            spokenWords: ["thin", "man"]
        )

        #expect(result.states == [.skipped, .matched, .matched])
    }

    @Test func nearMissesAreCloseSpellingsOnly() {
        #expect(ReadAloudService.isNearMiss("free", of: "three"))
        #expect(ReadAloudService.isNearMiss("tin", of: "thin"))
        #expect(ReadAloudService.isNearMiss("ask", of: "asked"))
        #expect(!ReadAloudService.isNearMiss("um", of: "the"))
        #expect(!ReadAloudService.isNearMiss("zebra", of: "the"))
        #expect(!ReadAloudService.isNearMiss("the", of: "the"))
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

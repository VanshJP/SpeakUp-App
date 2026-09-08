import Foundation
import Testing
@testable import SpeakUp


struct CoherenceParsingTests {
    private let block = """
    SCORE: 78
    TOPIC_FOCUS: Stayed on the hiring question
    LOGICAL_FLOW: Point, example, close
    REASON: Clear arc with one detour
    """

    @Test func readsTheFullBlock() {
        let result = CoherenceResult(parsing: block)
        #expect(result.score == 78)
        #expect(result.topicFocus == "Stayed on the hiring question")
        #expect(result.logicalFlow == "Point, example, close")
        #expect(result.reason == "Clear arc with one detour")
    }

    @Test func labelsAreCaseInsensitive() {
        #expect(CoherenceResult(parsing: "score: 61").score == 61)
    }

    @Test func scoreIsClampedToTheBand() {
        #expect(CoherenceResult(parsing: "SCORE: 140").score == 100)
    }

    @Test func aMinusSignIsNotAScore() {
        #expect(CoherenceResult(parsing: "SCORE: -20").score == 20)
    }

    @Test func proseWithoutLabelsStillScores() {
        // A chatty model should cost the user its reasoning, not its read.
        let result = CoherenceResult(parsing: "I'd rate this about 64 out of 100.")
        #expect(result.score == 64)
        #expect(result.topicFocus.isEmpty)
    }

    @Test func outOfBandNumbersAreIgnoredByTheFallback() {
        #expect(CoherenceResult(parsing: "Model v2024 scored 83 here").score == 83)
    }

    @Test func nothingNumericLandsOnTheNeutralMidpoint() {
        #expect(CoherenceResult(parsing: "I cannot assess this.").score == 50)
    }
}

struct NearestWordIndexTests {
    private func words(_ starts: [TimeInterval]) -> [TranscriptionWord] {
        starts.enumerated().map { index, start in
            TranscriptionWord(word: "w\(index)", start: start, end: start + 0.2, confidence: 1)
        }
    }

    @Test func emptyTranscriptHasNoIndex() {
        #expect([TranscriptionWord]().nearestIndex(to: 1.0) == nil)
    }

    @Test func exactStampWins() {
        #expect(words([0.0, 1.0, 2.0]).nearestIndex(to: 1.0) == 1)
    }

    @Test func closeStampSnapsToTheNearestWord() {
        #expect(words([0.0, 1.0, 2.0]).nearestIndex(to: 1.05) == 1)
    }

    @Test func coarseStampFallsForwardToRealSpeech() {
        #expect(words([0.0, 1.0, 5.0]).nearestIndex(to: 3.0) == 2)
    }

    @Test func stampPastTheLastWordHasNoIndex() {
        #expect(words([0.0, 1.0]).nearestIndex(to: 9.0) == nil)
    }
}

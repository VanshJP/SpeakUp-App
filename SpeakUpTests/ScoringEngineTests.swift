import Testing
import Foundation
@testable import SpeakUp

// Pure, deterministic scoring math — the substance multiplier, gibberish gate,
// and MATTR are the gates every score passes through, so they get the tests.

@MainActor
struct SubstanceMultiplierTests {
    @Test func zeroSubstanceCollapsesScore() {
        #expect(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 0) == 10)
    }

    @Test func fullSubstanceKeepsScoreNearlyIntact() {
        let result = SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 100)
        #expect(result >= 99)
    }

    @Test func bandsMatchDocumentedCurve() {
        // Interior points of each band (boundaries are float-sensitive).
        #expect(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 5) <= 20)
        #expect((25...65).contains(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 20)))
        #expect((65...88).contains(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 40)))
        #expect((88...97).contains(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 60)))
        #expect(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 90) >= 97)
    }

    @Test func multiplierIsMonotonic() {
        var previous = 0
        for substance in stride(from: 0, through: 100, by: 5) {
            let score = SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: substance)
            #expect(score >= previous, "score dropped between substance \(substance - 5) and \(substance)")
            previous = score
        }
    }

    @Test func neverExceedsOriginalOrBounds() {
        #expect(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 0, substanceScore: 100) == 0)
        #expect(SpeechScoringEngine.applySubstanceMultiplier(overallScore: 100, substanceScore: 100) <= 100)
    }
}

@MainActor
struct GibberishGateTests {
    @Test func definiteGibberishCapsAtEight() {
        #expect(SpeechScoringEngine.applyGibberishGate(score: 90, gibberishConfidence: 0.9) == 8)
        #expect(SpeechScoringEngine.applyGibberishGate(score: 5, gibberishConfidence: 0.9) == 5)
    }

    @Test func likelyGibberishCapsAtFifteen() {
        #expect(SpeechScoringEngine.applyGibberishGate(score: 90, gibberishConfidence: 0.7) == 15)
    }

    @Test func suspiciousCapsAtThirty() {
        #expect(SpeechScoringEngine.applyGibberishGate(score: 90, gibberishConfidence: 0.5) == 30)
    }

    @Test func cleanSpeechPassesThrough() {
        #expect(SpeechScoringEngine.applyGibberishGate(score: 90, gibberishConfidence: 0.2) == 90)
        #expect(SpeechScoringEngine.applyGibberishGate(score: 90, gibberishConfidence: 0.0) == 90)
    }
}

@MainActor
struct MATTRTests {
    private func words(_ list: [String]) -> [TranscriptionWord] {
        list.enumerated().map { index, word in
            TranscriptionWord(word: word, start: Double(index), end: Double(index) + 0.4)
        }
    }

    @Test func emptyInputIsZero() {
        #expect(SpeechScoringEngine.computeMATTR(words: []) == 0)
    }

    @Test func allUniqueWordsScoreOne() {
        let unique = words(["alpha", "bravo", "charlie", "delta", "echo"])
        #expect(SpeechScoringEngine.computeMATTR(words: unique) == 1.0)
    }

    @Test func allRepeatedWordsScoreLow() {
        let repeated = words(Array(repeating: "same", count: 10))
        #expect(SpeechScoringEngine.computeMATTR(words: repeated) == 0.1)
    }

    @Test func singleCharacterWordsAreFilteredOut() {
        // "a"/"I" style tokens are excluded; nothing left → 0.
        #expect(SpeechScoringEngine.computeMATTR(words: words(["a", "b", "c"])) == 0)
    }

    @Test func mixedVarietyLandsBetweenExtremes() {
        let mixed = words(["speak", "clear", "speak", "loud", "speak", "slow"])
        let mattr = SpeechScoringEngine.computeMATTR(words: mixed)
        #expect(mattr > 0.1 && mattr < 1.0)
    }
}

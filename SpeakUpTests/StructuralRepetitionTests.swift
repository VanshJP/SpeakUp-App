import Testing
import Foundation
@testable import SpeakUp

/// Structural repetition (anaphora-as-tic) — same FillerWord shape as classic
/// fillers so the detail UI needs no second render path.

struct StructuralRepetitionTests {

    /// Evenly spaced words; trailing punctuation on a token marks a clause end.
    private func words(_ tokens: [String], gap: TimeInterval = 0.15) -> [TranscriptionWord] {
        var cursor: TimeInterval = 0
        return tokens.map { token in
            let start = cursor
            let end = start + 0.3
            cursor = end + gap
            return TranscriptionWord(
                word: token,
                start: start,
                end: end,
                isFiller: false,
                isPrimarySpeaker: true
            )
        }
    }

    // MARK: - Positive

    @Test func sockTomatoEggFlagsStructuralFrame() throws {
        // "I'm going to get socks, I'm going to get tomatoes, I'm going to get eggs."
        let transcript = words([
            "I'm", "going", "to", "get", "socks,",
            "I'm", "going", "to", "get", "tomatoes,",
            "I'm", "going", "to", "get", "eggs."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)

        #expect(hits.count == 1)
        let hit = try #require(hits.first)
        #expect(hit.count == 3)
        #expect(hit.timestamps.count == 3)
        // Surface form kept for the chip label (not the expanded "i am going").
        #expect(hit.word.contains("going"))
        #expect(hit.word.contains("i'm") || hit.word.contains("i am"))
    }

    @Test func contractionAndExpandedFormStillMatch() {
        // I'm / I am / I'm — same frame family after contraction expansion.
        let transcript = words([
            "I'm", "going", "to", "buy", "milk,",
            "I", "am", "going", "to", "buy", "bread,",
            "I'm", "going", "to", "buy", "eggs."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.count == 1)
        #expect(hits.first?.count == 3)
    }

    @Test func andBoundarySplitsClauses() {
        let transcript = words([
            "We", "need", "to", "ship", "today",
            "and", "we", "need", "to", "ship", "tomorrow",
            "and", "we", "need", "to", "ship", "Friday."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.count == 1)
        #expect(hits.first?.count == 3)
    }

    // MARK: - Negatives

    @Test func variedOpeningsDoNotFlag() {
        // No shared opening frame — should stay quiet.
        let transcript = words([
            "Today", "I", "bought", "socks,",
            "Later", "we", "grabbed", "tomatoes,",
            "Finally", "someone", "brought", "eggs."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.isEmpty)
    }

    @Test func twoRepeatsAreParallelismNotATic() {
        // minRunLength is 3 — a pair should not flag.
        let transcript = words([
            "I'm", "going", "to", "get", "socks,",
            "I'm", "going", "to", "get", "tomatoes."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.isEmpty)
    }

    @Test func emptyInputYieldsEmpty() {
        #expect(StructuralRepetitionDetector.detect(in: []).isEmpty)
    }

    @Test func nonPrimarySpeakerWordsIgnoredByCallerFilter() {
        // Detector itself trusts the caller to pass primary-only words.
        // Simulate that gate: interviewer turns never reach detect().
        let interviewer = words([
            "Can", "you", "tell", "me", "about,",
            "Can", "you", "tell", "me", "more,",
            "Can", "you", "tell", "me", "why."
        ]).map {
            TranscriptionWord(
                word: $0.word,
                start: $0.start,
                end: $0.end,
                isFiller: false,
                isPrimarySpeaker: false
            )
        }
        let primaryOnly = interviewer.filter(\.isPrimarySpeaker)
        #expect(StructuralRepetitionDetector.detect(in: primaryOnly).isEmpty)
    }
}

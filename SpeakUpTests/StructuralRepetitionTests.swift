import Testing
import Foundation
@testable import SpeakUp

/// Structural repetition (anaphora-as-tic) — same FillerWord shape as classic
/// fillers so the detail UI needs no second render path.

struct StructuralRepetitionTests {

    /// Evenly spaced words; trailing punctuation on a token marks a clause end.
    /// Pass `gap` ≥ `clausePauseThreshold` to simulate punctuation-poor Whisper.
    private func words(
        _ tokens: [String],
        gap: TimeInterval = 0.15,
        isPrimary: Bool = true
    ) -> [TranscriptionWord] {
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
                isPrimarySpeaker: isPrimary
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
        #expect(hit.kind == .structural)
        #expect(hit.word.contains("going"))
        #expect(hit.word.contains("i'm") || hit.word.contains("i am"))
    }

    @Test func contractionAndExpandedFormStillMatch() {
        let transcript = words([
            "I'm", "going", "to", "buy", "milk,",
            "I", "am", "going", "to", "buy", "bread,",
            "I'm", "going", "to", "buy", "eggs."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.count == 1)
        #expect(hits.first?.count == 3)
        #expect(hits.first?.kind == .structural)
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

    @Test func pauseGapsSplitWhenWhisperOmitsCommas() {
        // No trailing punctuation — only a pause between clauses (Whisper often
        // drops commas). Intra-clause word gaps stay under the threshold.
        var cursor: TimeInterval = 0
        func appendClause(_ tokens: [String], into result: inout [TranscriptionWord]) {
            for token in tokens {
                let start = cursor
                let end = start + 0.25
                result.append(TranscriptionWord(
                    word: token, start: start, end: end,
                    isFiller: false, isPrimarySpeaker: true
                ))
                cursor = end + 0.12
            }
            // Clause boundary pause (no comma on the last token).
            cursor += StructuralRepetitionDetector.clausePauseThreshold
        }

        var transcript: [TranscriptionWord] = []
        appendClause(["I'm", "going", "to", "get", "socks"], into: &transcript)
        appendClause(["I'm", "going", "to", "get", "tomatoes"], into: &transcript)
        appendClause(["I'm", "going", "to", "get", "eggs"], into: &transcript)

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.count == 1)
        #expect(hits.first?.count == 3)
    }

    @Test func nearConsecutiveAllowsOneInterveningClause() {
        let transcript = words([
            "I'm", "going", "to", "finish", "this,",
            "Meanwhile", "the", "clock", "keeps", "ticking,",
            "I'm", "going", "to", "finish", "that,",
            "I'm", "going", "to", "finish", "everything."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.count == 1)
        #expect(hits.first?.count == 3)
    }

    // MARK: - Negatives

    @Test func variedOpeningsDoNotFlag() {
        let transcript = words([
            "Today", "I", "bought", "socks,",
            "Later", "we", "grabbed", "tomatoes,",
            "Finally", "someone", "brought", "eggs."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.isEmpty)
    }

    @Test func twoRepeatsAreParallelismNotATic() {
        let transcript = words([
            "I'm", "going", "to", "get", "socks,",
            "I'm", "going", "to", "get", "tomatoes."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.isEmpty)
    }

    @Test func intentionalOrdinalListIsNotFlagged() {
        // Curriculum-style First/Second/Third — craft, not a tic.
        let transcript = words([
            "First", "we", "need", "alignment,",
            "Second", "we", "need", "budget,",
            "Third", "we", "need", "timeline."
        ])

        let hits = StructuralRepetitionDetector.detect(in: transcript)
        #expect(hits.isEmpty)
    }

    @Test func emptyInputYieldsEmpty() {
        #expect(StructuralRepetitionDetector.detect(in: []).isEmpty)
    }

    @Test func nonPrimarySpeakerWordsIgnoredByCallerFilter() {
        let interviewer = words([
            "Can", "you", "tell", "me", "about,",
            "Can", "you", "tell", "me", "more,",
            "Can", "you", "tell", "me", "why."
        ], isPrimary: false)
        let primaryOnly = interviewer.filter(\.isPrimarySpeaker)
        #expect(StructuralRepetitionDetector.detect(in: primaryOnly).isEmpty)
    }

    @Test func fillerWordKindDecodesMissingAsFiller() throws {
        // Old persisted analyses omit `kind` — must default to classic filler.
        let data = Data(#"{"word":"um","count":2,"timestamps":[1.0,2.0]}"#.utf8)
        let decoded = try JSONDecoder().decode(FillerWord.self, from: data)
        #expect(decoded.kind == .filler)
        #expect(decoded.word == "um")
        #expect(decoded.count == 2)
    }

    @Test func sessionHitsSurfaceStructuralCategory() throws {
        let transcript = words([
            "I'm", "going", "to", "get", "socks,",
            "I'm", "going", "to", "get", "tomatoes,",
            "I'm", "going", "to", "get", "eggs."
        ])
        let hits = LexiconInsightsEngine.sessionHits(from: transcript)
        let structural = hits.filter { $0.category == .structural }
        #expect(!structural.isEmpty)
        let hit = try #require(structural.first)
        #expect(hit.count >= 3)
        #expect(hit.occurrences.first?.options.isEmpty == false)
    }
}

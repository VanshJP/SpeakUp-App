import Testing
import Foundation
@testable import SpeakUp

@Suite("Word Swap Suggestions")
struct WordSwapTests {

    private func timedWords(_ text: String, fillers: Set<String> = []) -> [TranscriptionWord] {
        var start = 0.0
        return text.split(separator: " ").map { raw in
            defer { start += 0.5 }
            return TranscriptionWord(
                word: String(raw),
                start: start,
                end: start + 0.4,
                isFiller: fillers.contains(String(raw))
            )
        }
    }

    private func hit(_ hits: [SessionWordHit], _ word: String) -> SessionWordHit? {
        hits.first { $0.word == word }
    }

    // MARK: Disambiguation — like

    @Test
    func likeBeforeNumberSuggestsAbout() {
        let words = timedWords(
            "we shipped it in like three weeks and still hit every date",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        #expect(like?.primarySwap?.replacement == "\u{201C}about\u{201D}")
        #expect(like?.primarySwap?.cue == "before numbers")
    }

    @Test
    func likeBeforeExampleNounPhraseSuggestsSuchAs() {
        let words = timedWords(
            "our platforms like the dashboard all shipped early this year",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        #expect(like?.primarySwap?.replacement == "\u{201C}such as\u{201D}")
        #expect(like?.swaps.contains("\u{201C}for example\u{201D}") == true)
    }

    @Test
    func likeAfterPerceptionVerbSuggestsAsIf() {
        let words = timedWords(
            "it feels like we rushed the rollout quite badly",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        #expect(like?.primarySwap?.replacement == "\u{201C}as if\u{201D}")
    }

    @Test
    func likeMidSentenceHedgeDefaultsToPause() {
        let words = timedWords(
            "the launch was kind of messy and like nobody minded much",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        #expect(like?.primarySwap?.replacement == "a silent pause")
        #expect(like?.swaps.contains("cut it entirely") == true)
    }

    // MARK: Disambiguation — confirmation markers

    @Test
    func rightAtSentenceEndGetsConfirmationCheckOnce() {
        let words = timedWords("we shipped on time right", fillers: ["right"])

        let right = hit(LexiconInsightsEngine.sessionHits(from: words), "right")

        #expect(right?.primarySwap?.replacement == "hold silence \u{2014} let it land")
        #expect(right?.swaps.contains("\u{201C}Does that make sense?\u{201D}, at most once") == true)
    }

    @Test
    func rightMidSentenceOnlyGetsAPause() {
        let words = timedWords("the right call here is testing twice", fillers: ["right"])

        let right = hit(LexiconInsightsEngine.sessionHits(from: words), "right")

        #expect(right?.primarySwap?.replacement == "a silent pause")
    }

    // MARK: Hedges and softeners

    @Test
    func reallyPlusAdjectiveSuggestsTheStrongerWord() {
        let words = timedWords("the demo was really good overall folks")

        let really = hit(LexiconInsightsEngine.sessionHits(from: words), "really")

        #expect(really?.primarySwap?.replacement == "\u{201C}excellent\u{201D}")
        #expect(really?.primarySwap?.cue == "one strong word beats two")
    }

    @Test
    func justWantDropsTheMinimizer() {
        let words = timedWords("i just want to add one point here")

        let just = hit(LexiconInsightsEngine.sessionHits(from: words), "just")

        #expect(just?.primarySwap?.replacement == "\u{201C}I want\u{201D}")
        #expect(just?.primarySwap?.cue?.contains("state the ask") == true)
    }

    @Test
    func kindOfBeforeVerbSaysStateItDirectly() {
        let words = timedWords("we kind of rushed the migration out fast")

        let kindOf = hit(LexiconInsightsEngine.sessionHits(from: words), "kind of")

        #expect(kindOf?.category == .hedge)
        #expect(kindOf?.primarySwap?.replacement.hasPrefix("drop it") == true)
    }

    // MARK: Vague nouns

    @Test
    func thingsLikeNamesTheReferentAlreadyPresent() {
        let words = timedWords("we handled things like planning early on purpose")

        let things = hit(LexiconInsightsEngine.sessionHits(from: words), "things")

        #expect(things?.category == .vague)
        #expect(things?.primarySwap?.replacement.contains("including planning") == true)
    }

    // MARK: a lot

    @Test
    func aLotBecomesAHabitRowWithConcreteAdvice() {
        let words = timedWords("we traveled a lot this quarter honestly speaking")

        let hits = LexiconInsightsEngine.sessionHits(from: words)

        let aLot = hit(hits, "a lot")
        #expect(aLot?.category == .hedge)
        #expect(aLot?.count == 1)
        #expect(aLot?.timestamps.count == 1)
        #expect(aLot?.primarySwap?.replacement == "\u{201C}often\u{201D}")

        // The phrase consumed its own tokens — nothing double-counted.
        #expect(hit(hits, "lot") == nil)
    }

    // MARK: Longest-first consumption still holds

    @Test
    func notReallySureConsumesItsReallyAndKeepsMappedSwaps() {
        let words = timedWords("not really sure about the timeline i think maybe tuesday")

        let hits = LexiconInsightsEngine.sessionHits(from: words)

        #expect(hits.contains { $0.word == "not really sure" })
        #expect(!hits.contains { $0.word == "really" })

        let hedge = hit(hits, "not really sure")
        #expect(hedge?.category == .hedge)
        #expect(hedge?.swaps.first == "\u{201C}Let me think out loud\u{201D}")
        #expect(hedge?.occurrences.count == 1)
    }

    // MARK: Row-level ranking

    @Test
    func dominantPatternWinsWithEarliestTieBreak() {
        let words = timedWords(
            "we shipped like three platforms and platforms like the dashboard landed",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        // Two different patterns, one occurrence each: earliest wins the row,
        // and the winner's own fallback fills the third chip.
        #expect(like?.count == 2)
        #expect(like?.swaps == ["\u{201C}about\u{201D}", "\u{201C}such as\u{201D}", "\u{201C}roughly\u{201D}"])
        #expect(like?.exampleFragment?.contains(where: \.isTarget) == true)
    }

    @Test
    func mostFrequentPatternBeatsAnEarlierOneOff() {
        let words = timedWords(
            "like the dashboard shipped then tools like Figma like Slack synced",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        // "such as" fires twice, "cut it" (sentence-initial) once: majority wins.
        #expect(like?.count == 3)
        #expect(like?.swaps.first == "\u{201C}such as\u{201D}")
    }

    @Test
    func suggestionsAreDeterministicAcrossRuns() {
        let words = timedWords(
            "it feels like we rushed and like the metrics were really good basically",
            fillers: ["like"]
        )

        let first = LexiconInsightsEngine.sessionHits(from: words)
        let second = LexiconInsightsEngine.sessionHits(from: words)

        #expect(first == second)
        #expect(first.map(\.swaps) == second.map(\.swaps))
        #expect(first.compactMap(\.primarySwap) == second.compactMap(\.primarySwap))
    }

    // MARK: Fragments

    @Test
    func fragmentWindowsSixWordsEachSideAndEllipsizes() {
        let text = "okay so we started the build in january um finished the core module by march and shipped everything else"
        let words = timedWords(text, fillers: ["um"])

        let um = hit(LexiconInsightsEngine.sessionHits(from: words), "um")
        let fragment = um?.exampleFragment

        #expect(fragment?.first?.text == "\u{2026}")
        #expect(fragment?.last?.text == "\u{2026}")
        // Ellipsis + 13 window words + ellipsis.
        #expect(fragment?.count == 15)

        let targetIndex = fragment?.firstIndex(where: \.isTarget)
        #expect(targetIndex == 7)
        #expect(fragment?[targetIndex ?? 0].text == "um")
    }

    @Test
    func shortTranscriptKeepsWholeSentenceWithoutEllipses() {
        let words = timedWords("um well done everyone", fillers: ["um"])

        let um = hit(LexiconInsightsEngine.sessionHits(from: words), "um")

        // ±6 words spans the whole take, so nothing is truncated away.
        #expect(um?.exampleFragment?.map(\.text) == ["um", "well", "done", "everyone"])
        #expect(um?.exampleFragment?.first?.isTarget == true)
    }

    // MARK: Degenerate input and compatibility

    @Test
    func emptyInputYieldsNoHits() {
        #expect(LexiconInsightsEngine.sessionHits(from: []).isEmpty)
    }

    @Test
    func singleTokenStillCarriesOccurrenceData() {
        let words = timedWords("um")

        let hits = LexiconInsightsEngine.sessionHits(from: words)

        #expect(hits.count == 1)
        #expect(hits[0].count == 1)
        #expect(hits[0].timestamps == [0.0])
        #expect(hits[0].occurrences.count == 1)
        #expect(hits[0].primarySwap != nil)
    }

    @Test
    func occurrencesStayAlignedWithTimestamps() {
        let words = timedWords("um okay so um fine um done", fillers: ["um"])

        let um = hit(LexiconInsightsEngine.sessionHits(from: words), "um")

        #expect(um?.timestamps == [0.0, 1.5, 2.5])
        #expect(um?.occurrences.map(\.timestamp) == um?.timestamps)
    }

    @Test
    func handBuiltHitsKeepLegacySwapBehavior() {
        let unmappedVague = SessionWordHit(word: "zzzunmapped", category: .vague, count: 4, timestamps: [])
        #expect(unmappedVague.swaps == ["name the specifics"])
        #expect(unmappedVague.primarySwap == nil)
        #expect(unmappedVague.exampleFragment == nil)

        let mappedFiller = SessionWordHit(word: "very", category: .intensifier, count: 2, timestamps: [])
        #expect(mappedFiller.swaps.count >= 3)
        #expect(LexiconInsightsEngine.alternativesFor("very") != nil)
    }
}

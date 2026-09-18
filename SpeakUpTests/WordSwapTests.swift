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

    // MARK: Disambiguation - like

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

    // MARK: Disambiguation - confirmation markers

    @Test
    func rightAtSentenceEndGetsConfirmationCheckOnce() {
        let words = timedWords("we shipped on time right", fillers: ["right"])

        let right = hit(LexiconInsightsEngine.sessionHits(from: words), "right")

        #expect(right?.primarySwap?.replacement == "hold silence. Let it land")
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

        // The phrase consumed its own tokens - nothing double-counted.
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

    // MARK: Rewritten lines

    @Test
    func deleteSwapRewritesTheSentenceWithoutTheCrutch() {
        let words = timedWords("i just want to add one point here")

        let just = hit(LexiconInsightsEngine.sessionHits(from: words), "just")

        #expect(just?.occurrences.first?.rewritten?.map(\.text)
                == ["i", "want", "to", "add", "one", "point", "here"])
    }

    @Test
    func replaceSwapShowsTheStrongerWordInsideTheRewrite() {
        let words = timedWords("the demo was really good overall folks")

        let really = hit(LexiconInsightsEngine.sessionHits(from: words), "really")
        let rewritten = really?.occurrences.first?.rewritten

        // "really good" collapses to one word, not "excellent good".
        #expect(rewritten?.map(\.text) == ["the", "demo", "was", "excellent", "overall", "folks"])
        #expect(rewritten?.filter(\.isTarget).map(\.text) == ["excellent"])
    }

    @Test
    func deletedSentenceFinalTagKeepsItsPunctuation() {
        let words = timedWords("we shipped on time right.", fillers: ["right."])

        let right = hit(LexiconInsightsEngine.sessionHits(from: words), "right")

        #expect(right?.occurrences.first?.rewritten?.map(\.text)
                == ["we", "shipped", "on", "time."])
    }

    @Test
    func adviceOnlySwapOffersNoRewrite() {
        let words = timedWords("we handled things like planning early on purpose")

        let things = hit(LexiconInsightsEngine.sessionHits(from: words), "things")

        // "name them: including planning" is coaching, not one substitution - 
        // a wrong rewrite would be worse than none.
        #expect(things?.primarySwap?.edit.isMechanical == false)
        #expect(things?.occurrences.first?.rewritten == nil)
    }

    // MARK: Redundant advice

    @Test
    func identicalDeletionsCollapseToOneChip() {
        let words = timedWords("we just shipped the thing")

        let just = hit(LexiconInsightsEngine.sessionHits(from: words), "just")

        // The alternatives map offers "cut it" and "drop it entirely" - the
        // same edit twice. Only one survives.
        #expect(just?.swaps == ["cut it", "\u{201C}only\u{201D} when counting matters"])
        #expect(just?.swaps.contains("drop \u{201C}just\u{201D} entirely") == false)
    }

    @Test
    func pauseAndCutStayDistinctBecauseTheCoachingDiffers() {
        let words = timedWords("the launch was messy and like nobody minded much", fillers: ["like"])

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        #expect(like?.swaps.contains("a silent pause") == true)
        #expect(like?.swaps.contains("cut it entirely") == true)
    }

    // MARK: Moments

    @Test
    func occurrencesSharingAdviceCollapseIntoOneMoment() {
        let words = timedWords(
            "we shipped in like three weeks and fixed it in like five days",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        #expect(like?.count == 2)
        #expect(like?.moments.count == 1)
        #expect(like?.moments.first?.count == 2)
        #expect(like?.moments.first?.option.replacement == "\u{201C}about\u{201D}")
    }

    @Test
    func differentSentencePatternsBecomeSeparateMoments() {
        let words = timedWords(
            "we shipped like three platforms and platforms like the dashboard landed",
            fillers: ["like"]
        )

        let like = hit(LexiconInsightsEngine.sessionHits(from: words), "like")

        #expect(like?.moments.count == 2)
        #expect(like?.moments.map(\.option.replacement)
                == ["\u{201C}about\u{201D}", "\u{201C}such as\u{201D}"])
        #expect(like?.moments.allSatisfy { $0.count == 1 } == true)
    }

    @Test
    func alternatesNeverRepeatAMomentsOwnFix() {
        let words = timedWords("the demo was really good overall folks")

        let really = hit(LexiconInsightsEngine.sessionHits(from: words), "really")
        let primaries = Set(really?.moments.map(\.option.replacement) ?? [])

        #expect(really?.alternateOptions.contains { primaries.contains($0.replacement) } == false)
    }

    // MARK: Playability

    @Test
    func zeroStartOccurrenceIsNotOfferedAsAPlayPoint() {
        let words = timedWords("um okay so um fine um done", fillers: ["um"])

        let um = hit(LexiconInsightsEngine.sessionHits(from: words), "um")

        // Whisper emits zero starts often enough that tapping one jumps to the
        // top of the take - the transcript drops those taps too.
        #expect(um?.occurrences.first?.isPlayable == false)
        #expect(um?.occurrences.dropFirst().allSatisfy(\.isPlayable) == true)
    }

    // MARK: Sentence-aware fragments

    @Test
    func fragmentStartsAtTheSentenceItBelongsTo() {
        let words = timedWords("we shipped it. um the next thing landed", fillers: ["um"])

        let um = hit(LexiconInsightsEngine.sessionHits(from: words), "um")

        // The previous sentence is not context - quoting into it reads as a
        // glitch, and there is no leading ellipsis because nothing was cut.
        #expect(um?.exampleFragment?.map(\.text) == ["um", "the", "next", "thing", "landed"])
    }

    // MARK: Newly disambiguated words

    @Test
    func sentenceOpeningSelfHedgeIsToldToStateItDirectly() {
        let words = timedWords("we shipped early. i think the rollout was clean")

        let hedge = hit(LexiconInsightsEngine.sessionHits(from: words), "i think")

        #expect(hedge?.primarySwap?.replacement == "state it directly")
        #expect(hedge?.occurrences.first?.rewritten?.map(\.text)
                == ["The", "rollout", "was", "clean"])
    }

    @Test
    func midSentenceYouKnowIsCutRatherThanReplaced() {
        let words = timedWords("the migration was you know harder than planned")

        let filler = hit(LexiconInsightsEngine.sessionHits(from: words), "you know")

        #expect(filler?.primarySwap?.replacement == "cut it")
        #expect(filler?.occurrences.first?.rewritten?.map(\.text)
                == ["the", "migration", "was", "harder", "than", "planned"])
    }

    @Test
    func epistemicHedgeBeforeANumberBecomesARange() {
        let words = timedWords("it takes maybe three weeks end to end")

        let maybe = hit(LexiconInsightsEngine.sessionHits(from: words), "maybe")

        #expect(maybe?.primarySwap?.replacement == "\u{201C}about\u{201D}")
        #expect(maybe?.occurrences.first?.rewritten?.map(\.text)
                == ["it", "takes", "about", "three", "weeks", "end", "to", "end"])
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

// MARK: - Practice lines

@Suite("Word Swap Practice Lines")
struct WordSwapPracticeLineTests {

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

    @Test
    func rewrittenLineIsHandedOverAsPlainText() {
        let words = timedWords("i just want to add one point here")

        let just = hit(LexiconInsightsEngine.sessionHits(from: words), "just")

        #expect(just?.moments.first?.practiceLine == "i want to add one point here")
    }

    @Test
    func replacementLineCarriesTheStrongerWord() {
        let words = timedWords("the demo was really good overall folks")

        let really = hit(LexiconInsightsEngine.sessionHits(from: words), "really")

        #expect(really?.moments.first?.practiceLine == "the demo was excellent overall folks")
    }

    @Test
    func adviceWithoutARewriteHasNothingToPractice() {
        let words = timedWords("we handled things like planning early on purpose")

        let things = hit(LexiconInsightsEngine.sessionHits(from: words), "things")

        #expect(things?.moments.first?.practiceLine == nil)
    }

    @Test
    func tooShortALineIsNotARep() {
        let words = timedWords("we just shipped")

        let just = hit(LexiconInsightsEngine.sessionHits(from: words), "just")

        // "we shipped" is a fragment - sending it to a pronunciation scorer
        // would score nothing worth knowing.
        #expect(just?.occurrences.first?.rewritten != nil)
        #expect(just?.moments.first?.practiceLine == nil)
    }
}

// MARK: - Cross-take comparison

@Suite("Crutch Baseline")
struct CrutchBaselineTests {

    /// `count` filler tokens that are not crutch words, so only the words
    /// under test move the rate.
    private func padding(_ count: Int) -> String {
        Array(repeating: "topic", count: count).joined(separator: " ")
    }

    @Test
    func phrasesConsumeTheirTokensInPlainText() {
        let result = LexiconInsightsEngine.crutchCounts(in: "not really sure about the timeline you know")

        #expect(result.counts["not really sure"] == 1)
        #expect(result.counts["you know"] == 1)
        // The "really" inside the longer phrase must not count twice.
        #expect(result.counts["really"] == nil)
        #expect(result.words == 8)
    }

    @Test
    func baselineAveragesPerHundredWordRates() {
        let take = padding(24) + " just"

        let baseline = LexiconInsightsEngine.crutchBaseline(from: [take, take])

        #expect(baseline.takes == 2)
        #expect(baseline.rates["just"] == 4.0)
        #expect(baseline.isUsable)
    }

    @Test
    func aDroppedHabitPullsTheBaselineDown() {
        let withJust = padding(24) + " just"
        let without = padding(25)

        let baseline = LexiconInsightsEngine.crutchBaseline(from: [withJust, without])

        // Averaged over every rated take, not only the ones containing it.
        #expect(baseline.rates["just"] == 2.0)
    }

    @Test
    func takesTooShortToRateAreSkipped() {
        let baseline = LexiconInsightsEngine.crutchBaseline(from: ["just a few words"])

        #expect(baseline.takes == 0)
        #expect(baseline.isUsable == false)
    }

    @Test
    func comparisonReadsRatesNotRawCounts() {
        let baseline = CrutchBaseline(rates: ["just": 4.0], takes: 2)

        // Same rate as usual.
        #expect(baseline.direction(for: "just", count: 1, totalWords: 25) == .steady)
        // Twice the rate.
        #expect(baseline.direction(for: "just", count: 2, totalWords: 25) == .rising)
        // Same raw count, twice the words - that is progress, not a wash.
        #expect(baseline.direction(for: "just", count: 1, totalWords: 50) == .falling)
    }

    @Test
    func oneEarlierTakeIsAnAnecdoteNotAUsual() {
        let baseline = CrutchBaseline(rates: ["just": 4.0], takes: 1)

        #expect(baseline.direction(for: "just", count: 9, totalWords: 25) == nil)
    }

    @Test
    func aHabitWithNoHistoryGetsNoComparison() {
        let baseline = CrutchBaseline(rates: ["just": 4.0], takes: 5)

        // "More than usual" against a usual of zero invites the fair reply
        // that there is no usual.
        #expect(baseline.direction(for: "basically", count: 4, totalWords: 25) == nil)
    }
}

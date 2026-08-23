import Testing
import Foundation
import NaturalLanguage
@testable import SpeakUp

// Characterization tests for the untested SpeechScoringEngine core.
// These pin CURRENT behavior — bands and orderings, not desired values.

// NLTagger(.lexicalClass) support varies by runtime state: fully provisioned,
// partially provisioned (function words only — observed on a freshly-erased
// sim mid-download), or absent. Strict lexical pins assume FULL support, so
// the probe measures the recognized ratio on real prose with the engine's own
// tag set; anything less runs bounds/threshold-invariant assertions only.
enum NLPCapability {
    static let fullLexicalSupport: Bool = {
        let text = "Daily practice built my speaking confidence steadily. Ambitious projects taught careful planning last year. Clear delivery helps nervous speakers succeed everywhere today."
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let known = SpeechScoringEngine.gibberishKnownTags
        var total = 0.0
        var recognized = 0.0
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, _ in
            total += 1
            if let tag, known.contains(tag) { recognized += 1 }
            return true
        }
        guard total > 0 else { return false }
        return recognized / total >= 0.85
    }()
}

// MARK: - detectGibberish

@Suite("Gibberish Detection Characterization")
struct GibberishDetectionCharacterizationTests {
    private let cleanText = "Daily practice built my speaking confidence steadily. Ambitious projects taught careful planning last year. Clear delivery helps nervous speakers succeed everywhere today. Thoughtful feedback improved every presentation quickly. Consistent rehearsal matters most."
    private let cleanWordList = ["daily", "practice", "built", "my", "speaking", "confidence",
                                 "steadily", "ambitious", "projects", "taught", "careful",
                                 "planning", "last", "year", "clear", "delivery", "helps",
                                 "nervous", "speakers", "succeed", "everywhere", "today",
                                 "thoughtful", "feedback", "improved", "every", "presentation",
                                 "quickly", "consistent", "rehearsal"]

    private func makeWords(_ list: [String], confidence: Double? = nil) -> [TranscriptionWord] {
        list.enumerated().map { index, word in
            TranscriptionWord(word: word, start: Double(index), end: Double(index) + 0.4, confidence: confidence)
        }
    }

    @Test func emptyInputAlwaysFlagsAsDefiniteGibberish() {
        let noWords = SpeechScoringEngine.detectGibberish(words: [], scoringText: cleanText)
        let noText = SpeechScoringEngine.detectGibberish(words: makeWords(cleanWordList), scoringText: "")
        for result in [noWords, noText] {
            #expect(result.confidence == 1.0)
            #expect(result.isDefinitelyGibberish)
            #expect(result.reason == "No speech detected")
        }
    }

    @Test func cleanEnglishParagraphPassesEverySignal() {
        let result = SpeechScoringEngine.detectGibberish(
            words: makeWords(cleanWordList, confidence: 0.92),
            scoringText: cleanText)
        if NLPCapability.fullLexicalSupport {
            #expect(!result.isDefinitelyGibberish)
            #expect(result.confidence == 0)
            #expect(result.reason == nil)
        } else {
            // Partial or missing NLP assets: recognition ratios land anywhere,
            // so pin the engine's threshold invariant instead of a shape.
            #expect(result.isDefinitelyGibberish == (result.confidence >= 4.0 / 6.0))
        }
    }

    @Test func randomConsonantStringsAreDefiniteGibberish() {
        // High ASR confidence on purpose: lexical signals alone must flag it.
        let text = "xkq zvw ptkl brwq znfj qlrm tvpk zjwq"
        let tokens = text.split(separator: " ").map(String.init)
        let result = SpeechScoringEngine.detectGibberish(
            words: makeWords(tokens, confidence: 0.95),
            scoringText: text)
        #expect(result.isDefinitelyGibberish)
        #expect(result.confidence >= 4.0 / 6.0)
    }

    @Test func repeatedSingleWordIsDefiniteGibberish() {
        let tokens = Array(repeating: "buffalo", count: 12)
        let result = SpeechScoringEngine.detectGibberish(
            words: makeWords(tokens),
            scoringText: tokens.joined(separator: " "))
        #expect(result.isDefinitelyGibberish)
        #expect(result.confidence >= 4.0 / 6.0)
        #expect(result.reason?.contains("repetition") == true)
    }

    @Test func whitespaceOnlyTextIsSuspiciousButNotDefinite() {
        // Whitespace slips past the empty guard; only the unique-content
        // check runs (+2 → 2/6). On runtimes without full NLP assets the
        // tokenizer still yields a token for the whitespace region, so the
        // lexical check can add +2 more.
        let result = SpeechScoringEngine.detectGibberish(words: makeWords(["hello"]), scoringText: "   ")
        if NLPCapability.fullLexicalSupport {
            #expect(!result.isDefinitelyGibberish)
            #expect(result.confidence > 0 && result.confidence <= 2.0 / 6.0)
        } else {
            #expect(result.isDefinitelyGibberish == (result.confidence >= 4.0 / 6.0))
        }
    }

    @Test func veryLowASRConfidenceFailsTwoChecks() {
        let result = SpeechScoringEngine.detectGibberish(
            words: makeWords(cleanWordList, confidence: 0.08),
            scoringText: cleanText)
        #expect(result.reason?.contains("confidence") == true)
        if NLPCapability.fullLexicalSupport {
            #expect(!result.isDefinitelyGibberish)
            #expect(result.confidence <= 2.0 / 6.0)
        } else {
            #expect(result.isDefinitelyGibberish == (result.confidence >= 4.0 / 6.0))
        }
    }

    @Test func inconsistentConfidenceWithLowMeanAddsVarianceSignal() {
        let mixed = cleanWordList.enumerated().map { index, word in
            TranscriptionWord(word: word, start: Double(index), end: Double(index) + 0.4,
                              confidence: index.isMultiple(of: 2) ? 0.05 : 0.85)
        }
        let result = SpeechScoringEngine.detectGibberish(words: mixed, scoringText: cleanText)
        #expect(result.reason?.contains("variance") == true)
        if NLPCapability.fullLexicalSupport {
            #expect(!result.isDefinitelyGibberish)
            #expect(result.confidence <= 2.0 / 6.0)
        } else {
            #expect(result.isDefinitelyGibberish == (result.confidence >= 4.0 / 6.0))
        }
    }
}

// MARK: - computeSubstanceScore

@Suite("Substance Score Characterization")
struct SubstanceScoreCharacterizationTests {
    private func score(
        nonFillers: Int,
        duration: TimeInterval = 60,
        mattr: Double = 0.8,
        density: Double = 25,
        mlr: Double = 10
    ) -> Int {
        SpeechScoringEngine.computeSubstanceScore(
            words: [],
            nonFillerCount: nonFillers,
            scoringText: "",
            actualDuration: duration,
            mattr: mattr,
            contentWordDensity: density,
            mlr: mlr)
    }

    @Test func fewerThanFiveNonFillersCapsAtFloorIgnoringQualityInputs() {
        let expected = [0, 2, 4, 6, 8]
        for (count, want) in expected.enumerated() {
            #expect(score(nonFillers: count, duration: 600, mattr: 1.0, density: 99, mlr: 15) == want)
        }
    }

    @Test func subThreeSecondDurationsCapAtFloorEvenWhenRich() {
        for duration in [0.0, 1.0, 2.0, 2.99] {
            let result = score(nonFillers: 80, duration: duration)
            #expect(result >= 0 && result <= 10)
        }
    }

    @Test func scoreNeverDecreasesAsNonFillerCountGrows() {
        var previous = 0
        for count in stride(from: 5, through: 140, by: 5) {
            let result = score(nonFillers: count)
            #expect(result >= previous, "score dropped between \(count - 5) and \(count) non-fillers")
            previous = result
        }
    }

    @Test func scoreNeverDecreasesAsDurationGrows() {
        var previous = 0
        for duration in stride(from: 3.0, through: 61.0, by: 2.0) {
            let result = score(nonFillers: 80, duration: duration)
            #expect(result >= previous, "score dropped between \(duration - 2)s and \(duration)s")
            previous = result
        }
    }

    @Test func scenarioBandsMatchDocumentedTuning() {
        let rich = score(nonFillers: 80, duration: 45, mattr: 0.9, density: 30, mlr: 12)
        #expect(rich >= 90)
        let mid = score(nonFillers: 40, duration: 25, mattr: 0.6, density: 15, mlr: 6)
        #expect((60...85).contains(mid))
        let poor = score(nonFillers: 15, duration: 4, mattr: 0.3, density: 2, mlr: 1)
        #expect((10...25).contains(poor))
    }

    @Test func absurdInputsClampToHundred() {
        #expect(score(nonFillers: 1_000, duration: 10_000, mattr: 1.0, density: 500, mlr: 100) <= 100)
    }
}

// MARK: - computeFluencyScore

@Suite("Fluency Score Characterization")
struct FluencyScoreCharacterizationTests {
    private func score(ptr: Double, mlr: Double, rate: Double) -> Int {
        SpeechScoringEngine.computeFluencyScore(
            phonationTimeRatio: ptr,
            mlr: mlr,
            articulationRate: rate,
            pauseMetadata: [PauseInfo(duration: 42, isTransition: true, startTime: 0)],
            actualDuration: 60)
    }

    @Test func idealZoneScoresPerfectHundred() {
        #expect(score(ptr: 0.6, mlr: 9, rate: 150) == 100)
    }

    @Test func silenceScoresZero() {
        #expect(score(ptr: 0, mlr: 0, rate: 0) == 0)
    }

    @Test func staysInBoundsAcrossWideParameterSweep() {
        for ptr in stride(from: 0.0, through: 1.0, by: 0.05) {
            for mlr in stride(from: 0.0, through: 12.0, by: 1.5) {
                for rate in stride(from: 0.0, through: 300.0, by: 25.0) {
                    let result = score(ptr: ptr, mlr: mlr, rate: rate)
                    #expect(result >= 0 && result <= 100)
                }
            }
        }
    }

    @Test func midRangePtrBeatsBothExtremes() {
        #expect(score(ptr: 0.6, mlr: 9, rate: 150) > score(ptr: 0.95, mlr: 9, rate: 150))
        #expect(score(ptr: 0.95, mlr: 9, rate: 150) > score(ptr: 0.05, mlr: 9, rate: 150))
    }

    @Test func extremeArticulationRateFloorsAtFivePoints() {
        #expect(score(ptr: 0.6, mlr: 10, rate: 10_000) == 75)
        #expect(score(ptr: 0.6, mlr: 10, rate: 240) == 90)
    }
}

// MARK: - computeMeanLengthOfRun

@Suite("Mean Length Of Run Tests")
struct MeanLengthOfRunTests {
    private func timed(_ spans: [(Double, Double)]) -> [TranscriptionWord] {
        spans.map { TranscriptionWord(word: "w", start: $0.0, end: $0.1) }
    }

    // Three groups of three words separated by 0.5s gaps. Dyadic offsets keep floats exact.
    private func groupedSpans() -> [(Double, Double)] {
        var spans: [(Double, Double)] = []
        for group in 0..<3 {
            for word in 0..<3 {
                let t = Double(group * 3 + word) * 0.5 + Double(group) * 0.5
                spans.append((t, t + 0.5))
            }
        }
        return spans
    }

    @Test func emptyInputReturnsZero() {
        #expect(SpeechScoringEngine.computeMeanLengthOfRun(words: [], pauseMetadata: []) == 0)
    }

    @Test func singleWordIsARunOfOne() {
        #expect(SpeechScoringEngine.computeMeanLengthOfRun(words: timed([(0.0, 0.5)]), pauseMetadata: []) == 1.0)
    }

    @Test func contiguousSpeechIsOneLongRun() {
        let spans = (0..<8).map { i -> (Double, Double) in (Double(i) * 0.5, Double(i) * 0.5 + 0.5) }
        #expect(SpeechScoringEngine.computeMeanLengthOfRun(words: timed(spans), pauseMetadata: []) == 8.0)
    }

    @Test func pausesSplitRunsIntoGroups() {
        #expect(SpeechScoringEngine.computeMeanLengthOfRun(words: timed(groupedSpans()), pauseMetadata: []) == 3.0)
    }

    @Test func gapOfQuarterSecondDoesNotSplitButHalfSecondDoes() {
        // Pins the >0.4s cutoff using dyadic offsets so the comparison is float-exact.
        let close = timed([(0.0, 1.0), (1.25, 1.75), (1.75, 2.25)])
        #expect(SpeechScoringEngine.computeMeanLengthOfRun(words: close, pauseMetadata: []) == 3.0)
        let far = timed([(0.0, 1.0), (1.5, 2.0), (2.0, 2.5)])
        #expect(SpeechScoringEngine.computeMeanLengthOfRun(words: far, pauseMetadata: []) == 1.5)
    }

    @Test func outOfOrderSegmentsSortBeforeGapDetection() {
        // WhisperKit can emit out-of-order segments; unsorted gaps once inflated MLR.
        let spans = groupedSpans()
        let sorted = SpeechScoringEngine.computeMeanLengthOfRun(words: timed(spans), pauseMetadata: [])
        let reversed = SpeechScoringEngine.computeMeanLengthOfRun(words: timed(Array(spans.reversed())), pauseMetadata: [])
        #expect(reversed == sorted)
        #expect(sorted == 3.0)
    }

    @Test func pauseMetadataIsAcceptedButIgnored() {
        let spans = (0..<8).map { i -> (Double, Double) in (Double(i) * 0.5, Double(i) * 0.5 + 0.5) }
        let junk = [PauseInfo(duration: 99, isTransition: true, startTime: 3)]
        let plain = SpeechScoringEngine.computeMeanLengthOfRun(words: timed(spans), pauseMetadata: [])
        let noisy = SpeechScoringEngine.computeMeanLengthOfRun(words: timed(spans), pauseMetadata: junk)
        #expect(noisy == plain)
    }
}

// MARK: - computeContentWordDensity

@Suite("Content Word Density Tests")
struct ContentWordDensityTests {
    private let richText = "Engineers presented detailed architecture diagrams explaining distributed systems thoroughly. Managers questioned reliability guarantees during deployment planning yesterday afternoon."
    private let sparseText = "He went to it again."

    @Test func emptyTextOrInvalidDurationReturnsZero() {
        #expect(SpeechScoringEngine.computeContentWordDensity(text: "", duration: 60) == 0)
        #expect(SpeechScoringEngine.computeContentWordDensity(text: richText, duration: 0) == 0)
        #expect(SpeechScoringEngine.computeContentWordDensity(text: richText, duration: -5) == 0)
    }

    @Test func punctuationOnlyTextYieldsZeroDensity() {
        #expect(SpeechScoringEngine.computeContentWordDensity(text: "?! ... !!!", duration: 60) == 0)
    }

    @Test func functionWordsAloneYieldNearZeroDensity() {
        let density = SpeechScoringEngine.computeContentWordDensity(
            text: "The of and to was he she it they", duration: 60)
        #expect(density < 1.0)
    }

    @Test func richerTextOutdensifiesSparseTextAtEqualDuration() {
        let rich = SpeechScoringEngine.computeContentWordDensity(text: richText, duration: 60)
        let sparse = SpeechScoringEngine.computeContentWordDensity(text: sparseText, duration: 60)
        if NLPCapability.fullLexicalSupport {
            #expect(rich > sparse)
        } else {
            #expect(rich >= 0 && sparse >= 0 && rich >= sparse)
        }
        #expect(sparse >= 0)
    }

    @Test func longerDurationLowersDensityForSameText() {
        let perMinute = SpeechScoringEngine.computeContentWordDensity(text: richText, duration: 60)
        let perTenMinutes = SpeechScoringEngine.computeContentWordDensity(text: richText, duration: 600)
        // Same text → same detected count → density is inversely proportional
        // to duration. Holds for any tagging capability, including zero.
        #expect(perTenMinutes <= perMinute)
        if NLPCapability.fullLexicalSupport {
            #expect(perTenMinutes > 0)
        }
    }

    @Test func realisticAnswerLandsInSanityBand() {
        let text = """
        Practicing public speaking every morning changed my career trajectory completely. \
        I recorded short answers, reviewed awkward phrasing, and replaced weak verbs with stronger choices. \
        Within months, interviews felt conversational instead of terrifying.
        """
        let density = SpeechScoringEngine.computeContentWordDensity(text: text, duration: 60)
        if NLPCapability.fullLexicalSupport {
            #expect(density >= 3 && density <= 60)
        } else {
            #expect(density >= 0)
        }
    }
}

// MARK: - computeLexicalSophisticationScore / computeWordRarityScore

@Suite("Lexical Sophistication Tests")
struct LexicalSophisticationTests {
    private func score(_ list: [String], mattr: Double) -> Int {
        let words = list.map { TranscriptionWord(word: $0, start: 0, end: 0.4) }
        return SpeechScoringEngine.computeLexicalSophisticationScore(
            words: words, mattr: mattr, scoringText: list.joined(separator: " "))
    }

    @Test func emptyWordsReturnZero() {
        #expect(score([], mattr: 0.9) == 0)
    }

    @Test func sophisticatedVocabularyOutscoresEverydayVocabulary() {
        let everyday = ["good", "work", "people", "time", "make"]
        let fancy = ["quintessential", "serendipitous", "idiosyncratic", "ephemeral", "perspicacious"]
        // Same MATTR handed to both — only word length and rarity differ.
        #expect(score(fancy, mattr: 0.7) > score(everyday, mattr: 0.7))
    }

    @Test func higherMattrNeverLowersScore() {
        let fancy = ["quintessential", "serendipitous", "idiosyncratic", "ephemeral", "perspicacious"]
        #expect(score(fancy, mattr: 0.9) > score(fancy, mattr: 0.2))
    }

    @Test func degenerateTokensStayBounded() {
        let punctuation = ["...", "???", "--", "!!"]
        let result = score(punctuation, mattr: 0.5)
        #expect(result >= 0 && result <= 100)
    }
}

// MARK: - computeEnhancedMetrics

@Suite("Enhanced Metrics Pipeline Tests")
struct EnhancedMetricsPipelineTests {
    private let paragraph = "Daily practice built my speaking confidence steadily. Ambitious projects taught careful planning last year. Clear delivery helps nervous speakers succeed everywhere today. Thoughtful feedback improved every presentation quickly. Consistent rehearsal matters most."
    private let wordList = ["daily", "practice", "built", "my", "speaking", "confidence",
                            "steadily", "ambitious", "projects", "taught", "careful",
                            "planning", "last", "year", "clear", "delivery", "helps",
                            "nervous", "speakers", "succeed", "everywhere", "today",
                            "thoughtful", "feedback", "improved", "every", "presentation",
                            "quickly", "consistent", "rehearsal"]

    private func timedWords(interleavingFillers: Bool) -> [TranscriptionWord] {
        var words: [TranscriptionWord] = []
        for (index, token) in wordList.enumerated() {
            let start = Double(index) * 0.5
            words.append(TranscriptionWord(word: token, start: start, end: start + 0.5, confidence: 0.92))
            if interleavingFillers && index.isMultiple(of: 2) {
                words.append(TranscriptionWord(word: "um", start: start + 0.5, end: start + 1.0, isFiller: true))
            }
        }
        return words
    }

    @Test func realisticParagraphProducesPopulatedCoherentMetrics() {
        let metrics = SpeechScoringEngine.computeEnhancedMetrics(
            words: timedWords(interleavingFillers: false),
            scoringText: paragraph,
            actualDuration: 30,
            pauseMetadata: [])

        #expect(metrics.phonationTimeRatio == 0.5)
        #expect(metrics.articulationRate == 120)
        #expect(metrics.meanLengthOfRun == 30)
        #expect(metrics.mattr == 1.0)
        #expect(metrics.fluencyScore == 100)
        #expect(metrics.substanceScore >= 0 && metrics.substanceScore <= 100)
        #expect(metrics.lexicalSophisticationScore >= 0 && metrics.lexicalSophisticationScore <= 100)
        if NLPCapability.fullLexicalSupport {
            #expect(metrics.contentWordDensity > 0)
            #expect(metrics.gibberishConfidence < 0.45)
            #expect(!metrics.isDefinitelyGibberish)
        } else {
            #expect(metrics.contentWordDensity >= 0)
            #expect(metrics.gibberishConfidence >= 0 && metrics.gibberishConfidence <= 1.0)
            #expect(metrics.isDefinitelyGibberish == (metrics.gibberishConfidence >= 4.0 / 6.0))
        }
        #expect(metrics.phonationTimeRatio.isFinite && metrics.contentWordDensity.isFinite)
    }

    @Test func fillerWordsExcludedFromMATTRAndArticulation() {
        // 30 content + 15 filler words, all 0.5s: voiced 22.5s, spoken 30 words.
        let metrics = SpeechScoringEngine.computeEnhancedMetrics(
            words: timedWords(interleavingFillers: true),
            scoringText: paragraph,
            actualDuration: 22.5,
            pauseMetadata: [])

        #expect(metrics.mattr == 1.0)
        #expect(metrics.articulationRate == 80)
    }

    @Test func deterministicAcrossCalls() {
        let first = SpeechScoringEngine.computeEnhancedMetrics(
            words: timedWords(interleavingFillers: false),
            scoringText: paragraph, actualDuration: 30, pauseMetadata: [])
        let second = SpeechScoringEngine.computeEnhancedMetrics(
            words: timedWords(interleavingFillers: false),
            scoringText: paragraph, actualDuration: 30, pauseMetadata: [])
        #expect(first == second)
    }

    @Test func emptyOrZeroDurationFallsBackToDefaults() {
        // Unlike detectGibberish, the pipeline reports no gibberish for empty input.
        let noWords = SpeechScoringEngine.computeEnhancedMetrics(
            words: [], scoringText: paragraph, actualDuration: 30, pauseMetadata: [])
        let noTime = SpeechScoringEngine.computeEnhancedMetrics(
            words: timedWords(interleavingFillers: false),
            scoringText: paragraph, actualDuration: 0, pauseMetadata: [])
        for metrics in [noWords, noTime] {
            #expect(metrics == EnhancedSpeechMetrics())
            #expect(metrics.gibberishConfidence == 0)
            #expect(!metrics.isDefinitelyGibberish)
        }
    }
}

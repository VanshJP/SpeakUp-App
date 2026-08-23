import Testing
import Foundation
@testable import SpeakUp

// End-to-end pins for SpeechAnalysisPipeline.analyze: a realistic transcription
// must come out with every subscore finite and bounded, a plausible WPM, and
// identical scoring across repeated calls. Exact lexical expectations are
// gated on NLPCapability (fresh simulators ship no NLP models); bounds hold
// everywhere.

@MainActor
struct PipelineSmokeTests {
    /// 57 words over ~39s: five sentences with 0.9s inter-sentence gaps
    /// (real pauses), two flagged fillers, Whisper-like confidences.
    /// Gross rate lands near 87 WPM — inside the plausibility band below.
    private func realisticTranscription() -> SpeechTranscriptionResult {
        let sentences: [[String]] = [
            ["daily", "practice", "um", "slowly", "rebuilt", "my", "speaking", "confidence",
             "after", "months", "of", "awkward", "pauses"],
            ["ambitious", "projects", "taught", "me", "careful", "planning", "because",
             "every", "deadline", "rewarded", "preparation", "over", "panic"],
            ["clear", "delivery", "helps", "nervous", "speakers", "succeed", "when",
             "rehearsal", "uh", "becomes", "habit"],
            ["thoughtful", "feedback", "improved", "each", "presentation", "until",
             "complex", "ideas", "felt", "simple"],
            ["consistent", "effort", "matters", "most", "so", "keep", "recording",
             "short", "answers", "regularly"]
        ]
        var words: [TranscriptionWord] = []
        var cursor = 0.5
        for sentence in sentences {
            for token in sentence {
                words.append(TranscriptionWord(
                    word: token,
                    start: cursor,
                    end: cursor + 0.45,
                    confidence: 0.92,
                    isFiller: token == "um" || token == "uh"
                ))
                cursor += 0.6
            }
            cursor += 0.9  // sentence gap > 0.4s → detected as a pause
        }
        return SpeechTranscriptionResult(
            text: sentences.map { $0.joined(separator: " ") }.joined(separator: ". ") + ".",
            words: words,
            duration: cursor
        )
    }

    private func assertSubscoresBounded(_ analysis: SpeechAnalysis) {
        #expect(analysis.speechScore.overall >= 0 && analysis.speechScore.overall <= 100)
        let s = analysis.speechScore.subscores
        #expect(s.clarity >= 0 && s.clarity <= 100)
        #expect(s.pace >= 0 && s.pace <= 100)
        #expect(s.fillerUsage >= 0 && s.fillerUsage <= 100)
        #expect(s.pauseQuality >= 0 && s.pauseQuality <= 100)
        for optional in [s.vocalVariety, s.delivery, s.vocabulary, s.structure, s.relevance] {
            if let value = optional {
                #expect(value >= 0 && value <= 100)
            }
        }
    }

    @Test func realisticTranscriptionProducesBoundedPlausibleAnalysis() {
        let input = realisticTranscription()
        let result = SpeechAnalysisPipeline.analyze(
            transcription: input,
            actualDuration: input.duration
        )

        #expect(result.totalWords == input.words.count)
        // Gross rate over the full recording: 57 words / ~39s ≈ 87 WPM.
        #expect(result.wordsPerMinute > 0 && result.wordsPerMinute < 400)
        // The 0.9s sentence gaps must register as pauses.
        #expect(result.pauseCount >= 4)
        #expect(result.averagePauseLength > 0)

        assertSubscoresBounded(result)

        if NLPCapability.fullLexicalSupport {
            #expect((result.enhancedMetrics?.gibberishConfidence ?? 1) < 0.45)
            #expect(result.enhancedMetrics?.isDefinitelyGibberish != true)
        } else {
            // Partial/absent NLP assets: pin the threshold invariant only.
            if let m = result.enhancedMetrics {
                #expect(m.isDefinitelyGibberish == (m.gibberishConfidence >= 4.0 / 6.0))
            }
        }
        // Coherence rides NLEmbedding, which can be missing even where the
        // tagger works — so only its bounds are pinned, never its presence.
        if let relevance = result.promptRelevanceScore {
            #expect(relevance >= 0 && relevance <= 100)
        }
    }

    @Test func analyzeIsDeterministicAcrossCalls() {
        // Not whole-struct Equatable: FillerWord/WPMDataPoint mint a fresh
        // UUID per call inside analyze, so identity noise would mask real
        // drift. Every deterministic field is compared instead.
        let input = realisticTranscription()
        let first = SpeechAnalysisPipeline.analyze(transcription: input, actualDuration: input.duration)
        let second = SpeechAnalysisPipeline.analyze(transcription: input, actualDuration: input.duration)

        #expect(first.speechScore == second.speechScore)
        #expect(first.totalWords == second.totalWords)
        #expect(first.wordsPerMinute == second.wordsPerMinute)
        #expect(first.pauseCount == second.pauseCount)
        #expect(first.averagePauseLength == second.averagePauseLength)
        #expect(first.strategicPauseCount == second.strategicPauseCount)
        #expect(first.hesitationPauseCount == second.hesitationPauseCount)
        #expect(first.clarity == second.clarity)
        // Optional metric payloads are UUID-free and must match exactly.
        #expect(first.enhancedMetrics == second.enhancedMetrics)
        #expect(first.vocabComplexity == second.vocabComplexity)
        #expect(first.sentenceAnalysis == second.sentenceAnalysis)
        #expect(first.rateVariation == second.rateVariation)
        #expect(first.emphasisMetrics == second.emphasisMetrics)
        #expect(first.energyArc == second.energyArc)
        #expect(first.textQuality == second.textQuality)
        // Filler tallies are stable even though their row IDs are not.
        #expect(first.fillerWords.map(\.word) == second.fillerWords.map(\.word))
        #expect(first.fillerWords.map(\.count) == second.fillerWords.map(\.count))
    }

    @Test func emptyWordsReturnNonCrashingDefaults() {
        // Characterization of the zero-score gate, not a designed product
        // decision: no speech → all zeros, no trap.
        let result = SpeechAnalysisPipeline.analyze(
            transcription: SpeechTranscriptionResult(text: "", words: [], duration: 12),
            actualDuration: 12
        )
        #expect(result.totalWords == 0)
        #expect(result.wordsPerMinute == 0)
        #expect(result.speechScore.overall == 0)
        #expect(result.clarity == 0)
        #expect(result.pauseCount == 0)
        #expect(result.speechScore.subscores.clarity == 0)
    }

    @Test func allFillerInputCollapsesThroughTheZeroGate() {
        // Characterization: every word flagged filler leaves zero non-fillers,
        // so the zero-score gate fires — WPM included — instead of scoring a
        // transcript that is 100% filler.
        let words = (0..<10).map { i in
            TranscriptionWord(word: "um", start: Double(i), end: Double(i) + 0.5,
                              confidence: 0.9, isFiller: true)
        }
        let result = SpeechAnalysisPipeline.analyze(
            transcription: SpeechTranscriptionResult(text: words.map(\.word).joined(separator: " "),
                                                     words: words, duration: 10),
            actualDuration: 10
        )
        #expect(result.totalWords == 10)
        #expect(result.speechScore.overall == 0)
        #expect(result.wordsPerMinute == 0)
    }
}

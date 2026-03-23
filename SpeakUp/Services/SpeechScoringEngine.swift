import Foundation
import NaturalLanguage

// MARK: - SpeechScoringEngine
//
// A comprehensive, research-backed speech scoring engine designed for on-device use.
//
// Design principles (sourced from ETS SpeechRater v5, Pearson Versant, PRAAT/Toastmasters research):
//
//  1. SUBSTANCE GATE: Gibberish or near-empty speech must score very low (≤10).
//     Profound, lengthy speech should score very high (80-100).
//
//  2. FLUENCY METRICS: Uses Phonation Time Ratio (PTR), Mean Length of Run (MLR),
//     and articulation rate — the three most predictive fluency features in academic literature.
//
//  3. LEXICAL RICHNESS: Uses MATTR (Moving Average Type-Token Ratio) over a 50-word
//     sliding window, which is length-invariant unlike simple TTR.
//
//  4. MULTI-SIGNAL GIBBERISH DETECTION: Combines ASR confidence variance, NL lexical
//     class recognition ratio, sentence length distribution, and repetition density.
//
//  5. CONTENT SUBSTANCE: Rewards informational density — unique content words per minute,
//     sentence complexity, and topic development.
//
//  6. MULTIPLICATIVE SUBSTANCE GATE: Short/empty/gibberish speech cannot score well
//     regardless of how "fluent" the few words were. The substance score acts as a
//     multiplier on the final score, not just a ceiling.
//
// All processing is 100% on-device using Apple NaturalLanguage framework.

enum SpeechScoringEngine {

    // MARK: - Public Entry Point

    /// Compute an enhanced set of speech quality metrics from a transcript and timing data.
    /// These metrics are designed to be fed into `calculateEnhancedSubscores(...)` in SpeechService.
    static func computeEnhancedMetrics(
        words: [TranscriptionWord],
        scoringText: String,
        actualDuration: TimeInterval,
        pauseMetadata: [PauseInfo]
    ) -> EnhancedSpeechMetrics {
        let nonFillerWords = words.filter { !$0.isFiller }
        let totalWords = words.count
        let nonFillerCount = nonFillerWords.count

        guard totalWords > 0, actualDuration > 0 else {
            return EnhancedSpeechMetrics()
        }

        // ── Phonation Time Ratio ─────────────────────────────────────────────────────
        // PTR = total voiced time / total recording time
        // Research benchmark: 0.55-0.75 is natural conversational speech.
        // Below 0.40 = too many pauses / hesitant. Above 0.85 = no breathing room.
        let totalVoicedTime = words.reduce(0.0) { $0 + max(0, $1.duration) }
        let phonationTimeRatio = min(1.0, totalVoicedTime / actualDuration)

        // ── Articulation Rate ────────────────────────────────────────────────────────
        // Words per minute during VOICED time only (excludes pauses).
        // This separates fluency from pace — a speaker can be slow but fluent.
        // Research benchmark: 160-220 syllables/min is natural English speech.
        // We approximate syllables as words * 1.5 (average English word ≈ 1.5 syllables).
        let articulationRate = totalVoicedTime > 0
            ? Double(nonFillerCount) / (totalVoicedTime / 60.0)
            : 0

        // ── Mean Length of Run (MLR) ─────────────────────────────────────────────────
        // Average number of words between pauses (>0.4s gaps).
        // Research: MLR > 8 indicates fluent speech. MLR < 4 indicates disfluency.
        let mlr = computeMeanLengthOfRun(words: words, pauseMetadata: pauseMetadata)

        // ── MATTR (Moving Average Type-Token Ratio) ──────────────────────────────────
        // Lexical diversity measure that is length-invariant (unlike simple TTR).
        // Uses a 50-word sliding window. Score range: 0.0 - 1.0.
        // Research benchmark: 0.70+ is rich vocabulary; 0.50 is repetitive.
        let mattr = computeMATTR(words: nonFillerWords, windowSize: 50)

        // ── Content Word Density ─────────────────────────────────────────────────────
        // Unique content words (nouns, verbs, adjectives, adverbs) per minute of speech.
        // This rewards substantive, informative speech.
        let contentWordDensity = computeContentWordDensity(
            text: scoringText,
            duration: actualDuration
        )

        // ── Substance Score ──────────────────────────────────────────────────────────
        // A composite score (0-100) that captures whether the speech has meaningful content.
        // This is the PRIMARY gate: gibberish or near-empty speech scores very low here.
        let substanceScore = computeSubstanceScore(
            words: words,
            nonFillerCount: nonFillerCount,
            scoringText: scoringText,
            actualDuration: actualDuration,
            mattr: mattr,
            contentWordDensity: contentWordDensity,
            mlr: mlr
        )

        // ── Enhanced Gibberish Detection ─────────────────────────────────────────────
        // Multi-signal detection combining confidence, lexical recognition, and structure.
        let gibberishResult = detectGibberish(
            words: words,
            scoringText: scoringText
        )

        // ── Fluency Score ────────────────────────────────────────────────────────────
        // Combines PTR, MLR, and articulation rate into a single fluency signal.
        let fluencyScore = computeFluencyScore(
            phonationTimeRatio: phonationTimeRatio,
            mlr: mlr,
            articulationRate: articulationRate,
            pauseMetadata: pauseMetadata,
            actualDuration: actualDuration
        )

        // ── Lexical Sophistication Score ─────────────────────────────────────────────
        // Combines MATTR with word rarity and average word length.
        let lexicalScore = computeLexicalSophisticationScore(
            words: nonFillerWords,
            mattr: mattr,
            scoringText: scoringText
        )

        return EnhancedSpeechMetrics(
            phonationTimeRatio: phonationTimeRatio,
            articulationRate: articulationRate,
            meanLengthOfRun: mlr,
            mattr: mattr,
            contentWordDensity: contentWordDensity,
            substanceScore: substanceScore,
            fluencyScore: fluencyScore,
            lexicalSophisticationScore: lexicalScore,
            gibberishConfidence: gibberishResult.confidence,
            gibberishReason: gibberishResult.reason,
            isDefinitelyGibberish: gibberishResult.isDefinitelyGibberish
        )
    }

    // MARK: - Substance Score

    /// Computes a 0-100 substance score that rewards meaningful, informative speech.
    /// This is the most important gate: gibberish or trivially short speech scores ≤15.
    static func computeSubstanceScore(
        words: [TranscriptionWord],
        nonFillerCount: Int,
        scoringText: String,
        actualDuration: TimeInterval,
        mattr: Double,
        contentWordDensity: Double,
        mlr: Double
    ) -> Int {
        // Gate 1: Absolute minimum — fewer than 8 non-filler words = near-zero
        guard nonFillerCount >= 8 else {
            let base = Double(nonFillerCount) / 8.0
            return max(0, min(10, Int(base * 10)))
        }

        // Gate 2: Duration minimum — less than 5 seconds = near-zero
        guard actualDuration >= 5.0 else {
            return max(0, min(10, Int(actualDuration / 5.0 * 10)))
        }

        var score = 0.0

        // Component 1: Word count adequacy (0-25 points)
        // 20 words = 10pts, 50 words = 18pts, 100+ words = 25pts
        let wordCountComponent: Double
        if nonFillerCount >= 100 {
            wordCountComponent = 25
        } else if nonFillerCount >= 50 {
            wordCountComponent = 18 + Double(nonFillerCount - 50) / 50.0 * 7
        } else if nonFillerCount >= 20 {
            wordCountComponent = 10 + Double(nonFillerCount - 20) / 30.0 * 8
        } else {
            wordCountComponent = Double(nonFillerCount - 8) / 12.0 * 10
        }
        score += wordCountComponent

        // Component 2: Duration adequacy (0-20 points)
        // 15s = 8pts, 30s = 14pts, 60s+ = 20pts
        let durationComponent: Double
        if actualDuration >= 60 {
            durationComponent = 20
        } else if actualDuration >= 30 {
            durationComponent = 14 + (actualDuration - 30) / 30.0 * 6
        } else if actualDuration >= 15 {
            durationComponent = 8 + (actualDuration - 15) / 15.0 * 6
        } else {
            durationComponent = (actualDuration - 5) / 10.0 * 8
        }
        score += durationComponent

        // Component 3: Lexical diversity via MATTR (0-20 points)
        // MATTR 0.5 = 5pts, 0.65 = 12pts, 0.80+ = 20pts
        let mattrComponent: Double
        if mattr >= 0.80 {
            mattrComponent = 20
        } else if mattr >= 0.65 {
            mattrComponent = 12 + (mattr - 0.65) / 0.15 * 8
        } else if mattr >= 0.50 {
            mattrComponent = 5 + (mattr - 0.50) / 0.15 * 7
        } else {
            mattrComponent = mattr / 0.50 * 5
        }
        score += mattrComponent

        // Component 4: Content word density (0-20 points)
        // 5 unique content words/min = 5pts, 15/min = 12pts, 30+/min = 20pts
        let densityComponent: Double
        if contentWordDensity >= 30 {
            densityComponent = 20
        } else if contentWordDensity >= 15 {
            densityComponent = 12 + (contentWordDensity - 15) / 15.0 * 8
        } else if contentWordDensity >= 5 {
            densityComponent = 5 + (contentWordDensity - 5) / 10.0 * 7
        } else {
            densityComponent = contentWordDensity / 5.0 * 5
        }
        score += densityComponent

        // Component 5: Mean Length of Run (0-15 points)
        // MLR < 3 = 0pts (very disfluent), MLR 6 = 8pts, MLR 12+ = 15pts
        let mlrComponent: Double
        if mlr >= 12 {
            mlrComponent = 15
        } else if mlr >= 6 {
            mlrComponent = 8 + (mlr - 6) / 6.0 * 7
        } else if mlr >= 3 {
            mlrComponent = (mlr - 3) / 3.0 * 8
        } else {
            mlrComponent = 0
        }
        score += mlrComponent

        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - Fluency Score

    /// Computes a 0-100 fluency score based on PTR, MLR, and articulation rate.
    /// This is separate from pace (WPM) — a speaker can be slow but fluent.
    static func computeFluencyScore(
        phonationTimeRatio: Double,
        mlr: Double,
        articulationRate: Double,
        pauseMetadata: [PauseInfo],
        actualDuration: TimeInterval
    ) -> Int {
        var score = 0.0

        // PTR component (0-35 points)
        // Ideal range: 0.55-0.75. Below 0.40 = too many pauses. Above 0.85 = no breathing.
        let ptrComponent: Double
        if phonationTimeRatio >= 0.55 && phonationTimeRatio <= 0.75 {
            ptrComponent = 35  // Ideal zone
        } else if phonationTimeRatio >= 0.45 && phonationTimeRatio < 0.55 {
            ptrComponent = 25 + (phonationTimeRatio - 0.45) / 0.10 * 10
        } else if phonationTimeRatio > 0.75 && phonationTimeRatio <= 0.85 {
            ptrComponent = 25 + (0.85 - phonationTimeRatio) / 0.10 * 10
        } else if phonationTimeRatio >= 0.35 && phonationTimeRatio < 0.45 {
            ptrComponent = 10 + (phonationTimeRatio - 0.35) / 0.10 * 15
        } else if phonationTimeRatio > 0.85 {
            ptrComponent = max(10, 25 - (phonationTimeRatio - 0.85) / 0.15 * 15)
        } else {
            // Very low PTR (< 0.35) — very hesitant
            ptrComponent = max(0, phonationTimeRatio / 0.35 * 10)
        }
        score += ptrComponent

        // MLR component (0-35 points)
        // Research: MLR > 8 is fluent. MLR < 4 is disfluent.
        let mlrComponent: Double
        if mlr >= 10 {
            mlrComponent = 35
        } else if mlr >= 6 {
            mlrComponent = 22 + (mlr - 6) / 4.0 * 13
        } else if mlr >= 4 {
            mlrComponent = 12 + (mlr - 4) / 2.0 * 10
        } else if mlr >= 2 {
            mlrComponent = 4 + (mlr - 2) / 2.0 * 8
        } else {
            mlrComponent = max(0, mlr / 2.0 * 4)
        }
        score += mlrComponent

        // Articulation rate component (0-30 points)
        // Natural English: ~120-180 words/min during voiced time.
        // Below 80 = very slow/hesitant. Above 220 = rushing.
        let articulationComponent: Double
        if articulationRate >= 120 && articulationRate <= 180 {
            articulationComponent = 30
        } else if articulationRate >= 90 && articulationRate < 120 {
            articulationComponent = 20 + (articulationRate - 90) / 30.0 * 10
        } else if articulationRate > 180 && articulationRate <= 220 {
            articulationComponent = 20 + (220 - articulationRate) / 40.0 * 10
        } else if articulationRate >= 60 && articulationRate < 90 {
            articulationComponent = 8 + (articulationRate - 60) / 30.0 * 12
        } else if articulationRate > 220 {
            articulationComponent = max(5, 20 - (articulationRate - 220) / 40.0 * 15)
        } else {
            articulationComponent = max(0, articulationRate / 60.0 * 8)
        }
        score += articulationComponent

        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - Lexical Sophistication Score

    /// Computes a 0-100 lexical sophistication score using MATTR and word complexity.
    static func computeLexicalSophisticationScore(
        words: [TranscriptionWord],
        mattr: Double,
        scoringText: String
    ) -> Int {
        guard !words.isEmpty else { return 0 }

        var score = 0.0

        // MATTR component (0-50 points) — primary signal
        let mattrComponent = min(50, mattr * 62.5)  // 0.80 MATTR → 50pts
        score += mattrComponent

        // Average word length component (0-25 points)
        // Longer words = more sophisticated vocabulary (on average)
        let cleaned = words.map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
        let avgWordLength = cleaned.isEmpty ? 0 : Double(cleaned.reduce(0) { $0 + $1.count }) / Double(cleaned.count)
        // 4 chars = 5pts, 5 chars = 12pts, 6 chars = 20pts, 7+ chars = 25pts
        let lengthComponent: Double
        if avgWordLength >= 7 {
            lengthComponent = 25
        } else if avgWordLength >= 6 {
            lengthComponent = 20 + (avgWordLength - 6) * 5
        } else if avgWordLength >= 5 {
            lengthComponent = 12 + (avgWordLength - 5) * 8
        } else if avgWordLength >= 4 {
            lengthComponent = 5 + (avgWordLength - 4) * 7
        } else {
            lengthComponent = max(0, avgWordLength / 4.0 * 5)
        }
        score += lengthComponent

        // NL embedding rarity component (0-25 points)
        // Words semantically distant from the 10 most common English words = rarer/more sophisticated
        let rarityComponent = computeWordRarityScore(words: cleaned) * 25.0
        score += rarityComponent

        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - MATTR Computation

    /// Computes Moving Average Type-Token Ratio over a sliding window.
    /// This is length-invariant unlike simple TTR, making it suitable for speeches of any length.
    /// windowSize = 50 is the standard in academic literature (Covington & McFall 2010).
    static func computeMATTR(words: [TranscriptionWord], windowSize: Int = 50) -> Double {
        let cleaned = words.map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.count >= 2 }

        guard cleaned.count >= 2 else {
            // For very short utterances, use simple TTR
            let unique = Set(cleaned).count
            return cleaned.isEmpty ? 0 : Double(unique) / Double(cleaned.count)
        }

        // If shorter than window, use simple TTR
        if cleaned.count <= windowSize {
            let unique = Set(cleaned).count
            return Double(unique) / Double(cleaned.count)
        }

        // Sliding window TTR
        var windowTTRs: [Double] = []
        for i in 0...(cleaned.count - windowSize) {
            let window = cleaned[i..<(i + windowSize)]
            let unique = Set(window).count
            windowTTRs.append(Double(unique) / Double(windowSize))
        }

        return windowTTRs.reduce(0, +) / Double(windowTTRs.count)
    }

    // MARK: - Mean Length of Run

    /// Computes the Mean Length of Run — average number of words between pauses.
    /// This is a key fluency metric used in PRAAT and academic speech analysis.
    static func computeMeanLengthOfRun(
        words: [TranscriptionWord],
        pauseMetadata: [PauseInfo]
    ) -> Double {
        guard !words.isEmpty else { return 0 }
        // Note: pauseMetadata is accepted for API consistency but we detect pauses
        // directly from word timing gaps (>0.4s) for accuracy.
        _ = pauseMetadata  // suppress unused parameter warning

        // Sort by start time to ensure correct gap detection.
        // The words array is usually sorted, but WhisperKit can occasionally produce
        // slightly out-of-order segments at segment boundaries. Using the unsorted
        // array caused incorrect gap calculations (negative gaps) which inflated MLR.
        let sorted = words.sorted { $0.start < $1.start }

        var runs: [Int] = []
        var currentRun = 0

        for i in sorted.indices {
            currentRun += 1
            let word = sorted[i]

            // Check if there's a pause after this word using safe index access
            let isLastWord = i == sorted.count - 1
            if isLastWord {
                // End of transcript — close the final run
                if currentRun > 0 { runs.append(currentRun) }
                currentRun = 0
            } else {
                let nextWordStart = sorted[i + 1].start
                let gapAfter = nextWordStart - word.end
                // Only count gaps > 0.4s as run boundaries (same threshold as pause detection)
                if gapAfter > 0.4 {
                    if currentRun > 0 { runs.append(currentRun) }
                    currentRun = 0
                }
            }
        }

        guard !runs.isEmpty else { return Double(words.count) }
        return Double(runs.reduce(0, +)) / Double(runs.count)
    }

    // MARK: - Content Word Density

    /// Computes unique content words per minute of speech.
    static func computeContentWordDensity(text: String, duration: TimeInterval) -> Double {
        guard !text.isEmpty, duration > 0 else { return 0 }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var contentWords = Set<String>()
        let contentTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb]
        let stopVerbs: Set<String> = ["be", "is", "are", "was", "were", "have", "has", "had",
                                       "do", "does", "did", "will", "would", "can", "could",
                                       "should", "may", "might", "shall", "get", "got", "go",
                                       "going", "come", "came", "make", "made", "take", "took",
                                       "know", "think", "say", "said", "see", "saw", "want"]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            guard let tag, contentTags.contains(tag) else { return true }
            let word = String(text[range]).lowercased()
            guard word.count >= 3, !stopVerbs.contains(word) else { return true }
            contentWords.insert(word)
            return true
        }

        let durationMinutes = duration / 60.0
        return Double(contentWords.count) / durationMinutes
    }

    // MARK: - Enhanced Gibberish Detection

    struct GibberishResult {
        let confidence: Double      // 0.0 = definitely real speech, 1.0 = definitely gibberish
        let reason: String?         // Human-readable reason for flagging
        let isDefinitelyGibberish: Bool  // Hard flag for score gating
    }

    /// Multi-signal gibberish detection.
    /// Returns a confidence score (0-1) and a hard flag for score gating.
    ///
    /// Signals used:
    ///   1. ASR confidence mean and variance (low confidence + high variance = likely noise/gibberish)
    ///   2. NL lexical class recognition ratio (real words vs unrecognized tokens)
    ///   3. Sentence length distribution (all very short sentences = fragmented/gibberish)
    ///   4. Repetition density (same word >40% of transcript = likely stuck/gibberish)
    ///   5. Minimum substance check (fewer than 5 unique content words = likely gibberish)
    static func detectGibberish(
        words: [TranscriptionWord],
        scoringText: String
    ) -> GibberishResult {
        guard !scoringText.isEmpty, !words.isEmpty else {
            return GibberishResult(confidence: 1.0, reason: "No speech detected", isDefinitelyGibberish: true)
        }

        var failedChecks = 0
        var reasons: [String] = []

        // Signal 1: ASR confidence check
        let confidences = words.compactMap { $0.confidence }
        if !confidences.isEmpty {
            let avgConf = confidences.reduce(0, +) / Double(confidences.count)
            let variance = confidences.reduce(0.0) { $0 + pow($1 - avgConf, 2) } / Double(confidences.count)
            let stddev = sqrt(variance)

            if avgConf < 0.25 {
                failedChecks += 2  // Strong signal — very low confidence
                reasons.append("very low ASR confidence (\(String(format: "%.2f", avgConf)))")
            } else if avgConf < 0.40 {
                failedChecks += 1
                reasons.append("low ASR confidence (\(String(format: "%.2f", avgConf)))")
            }

            // High variance with low mean = inconsistent noise, not speech
            if stddev > 0.35 && avgConf < 0.50 {
                failedChecks += 1
                reasons.append("high confidence variance with low mean")
            }
        }

        // Signal 2: NL lexical class recognition
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = scoringText
        var totalTokens = 0
        var recognizedTokens = 0
        let knownTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb, .pronoun,
                                      .determiner, .particle, .preposition, .conjunction,
                                      .interjection, .number]

        tagger.enumerateTags(in: scoringText.startIndex..<scoringText.endIndex,
                              unit: .word, scheme: .lexicalClass) { tag, _ in
            totalTokens += 1
            if let tag, knownTags.contains(tag) { recognizedTokens += 1 }
            return true
        }

        if totalTokens > 0 {
            let recognizedRatio = Double(recognizedTokens) / Double(totalTokens)
            if recognizedRatio < 0.35 {
                failedChecks += 2  // Strong signal
                reasons.append("very few recognized English words (\(String(format: "%.0f", recognizedRatio * 100))%)")
            } else if recognizedRatio < 0.55 {
                failedChecks += 1
                reasons.append("low recognized English word ratio (\(String(format: "%.0f", recognizedRatio * 100))%)")
            }
        }

        // Signal 3: Sentence length distribution
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = scoringText
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: scoringText.startIndex..<scoringText.endIndex) { range, _ in
            let s = String(scoringText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }

        if sentences.count >= 2 {
            let maxSentenceWords = sentences.map { $0.split(separator: " ").count }.max() ?? 0
            let avgSentenceWords = Double(sentences.reduce(0) { $0 + $1.split(separator: " ").count }) / Double(sentences.count)

            if maxSentenceWords <= 3 && sentences.count > 3 {
                failedChecks += 1
                reasons.append("all sentences very short (max \(maxSentenceWords) words)")
            }
            if avgSentenceWords < 2.5 {
                failedChecks += 1
                reasons.append("average sentence length very low (\(String(format: "%.1f", avgSentenceWords)) words)")
            }
        }

        // Signal 4: Repetition density
        let wordList = scoringText.lowercased().split(separator: " ").map {
            String($0).trimmingCharacters(in: .punctuationCharacters)
        }.filter { $0.count >= 2 }

        if wordList.count >= 5 {
            var wordFreq: [String: Int] = [:]
            for word in wordList { wordFreq[word, default: 0] += 1 }
            let maxFreq = wordFreq.values.max() ?? 0
            let repetitionRatio = Double(maxFreq) / Double(wordList.count)

            if repetitionRatio > 0.45 {
                failedChecks += 2  // Strong signal — one word dominates
                reasons.append("extreme word repetition (single word = \(String(format: "%.0f", repetitionRatio * 100))% of transcript)")
            } else if repetitionRatio > 0.30 {
                failedChecks += 1
                reasons.append("high word repetition")
            }
        }

        // Signal 5: Unique content words
        let tagger2 = NLTagger(tagSchemes: [.lexicalClass])
        tagger2.string = scoringText
        var uniqueContentWords = Set<String>()
        let contentTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb]
        tagger2.enumerateTags(in: scoringText.startIndex..<scoringText.endIndex,
                               unit: .word, scheme: .lexicalClass) { tag, range in
            guard let tag, contentTags.contains(tag) else { return true }
            let word = String(scoringText[range]).lowercased()
            if word.count >= 3 { uniqueContentWords.insert(word) }
            return true
        }

        if uniqueContentWords.count < 3 {
            failedChecks += 2
            reasons.append("fewer than 3 unique content words")
        } else if uniqueContentWords.count < 6 {
            failedChecks += 1
            reasons.append("very few unique content words (\(uniqueContentWords.count))")
        }

        // Determine result
        // failedChecks: 0-1 = real speech, 2-3 = suspicious, 4+ = likely gibberish
        let isDefinitelyGibberish = failedChecks >= 4
        let confidence = min(1.0, Double(failedChecks) / 6.0)
        let reason = reasons.isEmpty ? nil : reasons.joined(separator: "; ")

        return GibberishResult(
            confidence: confidence,
            reason: reason,
            isDefinitelyGibberish: isDefinitelyGibberish
        )
    }

    // MARK: - Word Rarity Score

    /// Returns a 0-1 score representing how rare/sophisticated the vocabulary is.
    /// Uses NLEmbedding distance from common words as a proxy for rarity.
    static func computeWordRarityScore(words: [String]) -> Double {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            // Fallback: use word length as proxy for rarity
            let avgLen = words.isEmpty ? 0 : Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
            return min(1.0, max(0, (avgLen - 3.0) / 6.0))
        }

        let commonWords = ["the", "is", "have", "that", "good", "make", "go", "see", "know",
                           "take", "get", "come", "say", "want", "look", "use", "find", "give"]
        let uniqueWords = Array(Set(words)).filter { $0.count >= 3 }

        var totalRarity = 0.0
        var countedWords = 0

        for word in uniqueWords.prefix(80) {  // Cap at 80 for performance
            guard embedding.contains(word) else { continue }
            var minDist = 2.0
            for common in commonWords {
                guard embedding.contains(common) else { continue }
                let dist = embedding.distance(between: word, and: common)
                minDist = min(minDist, dist)
            }
            // Distance 0-2; map 0.5=common→0, 1.0=moderate→0.5, 1.5+=rare→1.0
            let rarity = max(0, min(1.0, (minDist - 0.4) / 1.0))
            totalRarity += rarity
            countedWords += 1
        }

        guard countedWords > 0 else { return 0 }
        return totalRarity / Double(countedWords)
    }

    // MARK: - Overall Score with Substance Multiplier

    /// Applies the substance score as a multiplier on the overall score.
    /// This ensures that gibberish or near-empty speech cannot score well
    /// even if the few words spoken were "fluent."
    ///
    /// The multiplier curve:
    ///   substanceScore 0-15: multiplier 0.05-0.15 (score collapses to near-zero)
    ///   substanceScore 15-40: multiplier 0.15-0.55 (score heavily penalized)
    ///   substanceScore 40-65: multiplier 0.55-0.85 (moderate penalty)
    ///   substanceScore 65-85: multiplier 0.85-0.97 (slight penalty)
    ///   substanceScore 85-100: multiplier 0.97-1.00 (near-full score)
    static func applySubstanceMultiplier(overallScore: Int, substanceScore: Int) -> Int {
        let s = Double(substanceScore)
        let multiplier: Double

        if s <= 15 {
            multiplier = 0.05 + (s / 15.0) * 0.10
        } else if s <= 40 {
            multiplier = 0.15 + ((s - 15) / 25.0) * 0.40
        } else if s <= 65 {
            multiplier = 0.55 + ((s - 40) / 25.0) * 0.30
        } else if s <= 85 {
            multiplier = 0.85 + ((s - 65) / 20.0) * 0.12
        } else {
            multiplier = 0.97 + ((s - 85) / 15.0) * 0.03
        }

        return max(0, min(100, Int(Double(overallScore) * multiplier)))
    }

    // MARK: - Gibberish Score Gate

    /// Hard score gate for gibberish speech.
    /// More aggressive than the previous isLikelyGibberish check.
    static func applyGibberishGate(score: Int, gibberishConfidence: Double) -> Int {
        if gibberishConfidence >= 0.85 {
            // Definitely gibberish — score collapses to ≤8
            return min(score, 8)
        } else if gibberishConfidence >= 0.65 {
            // Very likely gibberish — cap at 15
            return min(score, 15)
        } else if gibberishConfidence >= 0.45 {
            // Suspicious — cap at 30
            return min(score, 30)
        }
        return score
    }
}

// MARK: - EnhancedSpeechMetrics

/// Container for all enhanced speech metrics computed by SpeechScoringEngine.
struct EnhancedSpeechMetrics: Codable {
    /// Phonation Time Ratio: fraction of recording time spent speaking (0-1).
    /// Research benchmark: 0.55-0.75 is natural conversational speech.
    var phonationTimeRatio: Double

    /// Articulation rate: words per minute during voiced time only (excludes pauses).
    /// Research benchmark: 120-180 WPM during voiced time is natural English.
    var articulationRate: Double

    /// Mean Length of Run: average words between pauses.
    /// Research benchmark: MLR > 8 is fluent; MLR < 4 is disfluent.
    var meanLengthOfRun: Double

    /// Moving Average Type-Token Ratio (50-word window).
    /// Research benchmark: 0.70+ is rich vocabulary; 0.50 is repetitive.
    var mattr: Double

    /// Unique content words per minute of speech.
    var contentWordDensity: Double

    /// Composite substance score (0-100).
    /// This is the primary gate: gibberish or near-empty speech scores ≤15.
    var substanceScore: Int

    /// Composite fluency score (0-100) based on PTR, MLR, and articulation rate.
    var fluencyScore: Int

    /// Lexical sophistication score (0-100) based on MATTR, word length, and rarity.
    var lexicalSophisticationScore: Int

    /// Gibberish confidence (0-1): 0 = definitely real speech, 1 = definitely gibberish.
    var gibberishConfidence: Double

    /// Human-readable reason for gibberish flagging (nil if not flagged).
    var gibberishReason: String?

    /// Hard gibberish flag for score gating.
    var isDefinitelyGibberish: Bool

    init(
        phonationTimeRatio: Double = 0,
        articulationRate: Double = 0,
        meanLengthOfRun: Double = 0,
        mattr: Double = 0,
        contentWordDensity: Double = 0,
        substanceScore: Int = 0,
        fluencyScore: Int = 0,
        lexicalSophisticationScore: Int = 0,
        gibberishConfidence: Double = 0,
        gibberishReason: String? = nil,
        isDefinitelyGibberish: Bool = false
    ) {
        self.phonationTimeRatio = phonationTimeRatio
        self.articulationRate = articulationRate
        self.meanLengthOfRun = meanLengthOfRun
        self.mattr = mattr
        self.contentWordDensity = contentWordDensity
        self.substanceScore = substanceScore
        self.fluencyScore = fluencyScore
        self.lexicalSophisticationScore = lexicalSophisticationScore
        self.gibberishConfidence = gibberishConfidence
        self.gibberishReason = gibberishReason
        self.isDefinitelyGibberish = isDefinitelyGibberish
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phonationTimeRatio = (try? container.decodeIfPresent(Double.self, forKey: .phonationTimeRatio)) ?? 0
        articulationRate = (try? container.decodeIfPresent(Double.self, forKey: .articulationRate)) ?? 0
        meanLengthOfRun = (try? container.decodeIfPresent(Double.self, forKey: .meanLengthOfRun)) ?? 0
        mattr = (try? container.decodeIfPresent(Double.self, forKey: .mattr)) ?? 0
        contentWordDensity = (try? container.decodeIfPresent(Double.self, forKey: .contentWordDensity)) ?? 0
        substanceScore = (try? container.decodeIfPresent(Int.self, forKey: .substanceScore)) ?? 0
        fluencyScore = (try? container.decodeIfPresent(Int.self, forKey: .fluencyScore)) ?? 0
        lexicalSophisticationScore = (try? container.decodeIfPresent(Int.self, forKey: .lexicalSophisticationScore)) ?? 0
        gibberishConfidence = (try? container.decodeIfPresent(Double.self, forKey: .gibberishConfidence)) ?? 0
        gibberishReason = try? container.decodeIfPresent(String.self, forKey: .gibberishReason)
        isDefinitelyGibberish = (try? container.decodeIfPresent(Bool.self, forKey: .isDefinitelyGibberish)) ?? false
    }
}

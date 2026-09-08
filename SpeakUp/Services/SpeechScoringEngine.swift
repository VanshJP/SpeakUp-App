import Foundation
import NaturalLanguage

// MARK: - SpeechScoringEngine

nonisolated enum SpeechScoringEngine {

    // MARK: - Public Entry Point

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

        let totalVoicedTime = words.reduce(0.0) { $0 + max(0, $1.duration) }
        let phonationTimeRatio = min(1.0, totalVoicedTime / actualDuration)

        let articulationRate = totalVoicedTime > 0
            ? Double(nonFillerCount) / (totalVoicedTime / 60.0)
            : 0

        let mlr = computeMeanLengthOfRun(words: words, pauseMetadata: pauseMetadata)

        let mattr = computeMATTR(words: nonFillerWords, windowSize: 50)

        let contentWordDensity = computeContentWordDensity(
            text: scoringText,
            duration: actualDuration
        )

        let substanceScore = computeSubstanceScore(
            words: words,
            nonFillerCount: nonFillerCount,
            scoringText: scoringText,
            actualDuration: actualDuration,
            mattr: mattr,
            contentWordDensity: contentWordDensity,
            mlr: mlr
        )

        let gibberishResult = detectGibberish(
            words: words,
            scoringText: scoringText
        )

        let fluencyScore = computeFluencyScore(
            phonationTimeRatio: phonationTimeRatio,
            mlr: mlr,
            articulationRate: articulationRate,
            pauseMetadata: pauseMetadata,
            actualDuration: actualDuration
        )

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

    static func computeSubstanceScore(
        words: [TranscriptionWord],
        nonFillerCount: Int,
        scoringText: String,
        actualDuration: TimeInterval,
        mattr: Double,
        contentWordDensity: Double,
        mlr: Double
    ) -> Int {
        guard nonFillerCount >= 5 else {
            let base = Double(nonFillerCount) / 5.0
            return max(0, min(10, Int(base * 10)))
        }

        guard actualDuration >= 3.0 else {
            return max(0, min(10, Int(actualDuration / 3.0 * 10)))
        }

        var score = 0.0

        let wordCountComponent: Double
        if nonFillerCount >= 70 {
            wordCountComponent = 25
        } else if nonFillerCount >= 35 {
            wordCountComponent = 18 + Double(nonFillerCount - 35) / 35.0 * 7
        } else if nonFillerCount >= 15 {
            wordCountComponent = 10 + Double(nonFillerCount - 15) / 20.0 * 8
        } else {
            wordCountComponent = Double(nonFillerCount - 5) / 10.0 * 10
        }
        score += wordCountComponent

        let durationComponent: Double
        if actualDuration >= 40 {
            durationComponent = 20
        } else if actualDuration >= 20 {
            durationComponent = 14 + (actualDuration - 20) / 20.0 * 6
        } else if actualDuration >= 10 {
            durationComponent = 8 + (actualDuration - 10) / 10.0 * 6
        } else {
            durationComponent = (actualDuration - 3) / 7.0 * 8
        }
        score += durationComponent

        let mattrComponent: Double
        if mattr >= 0.72 {
            mattrComponent = 20
        } else if mattr >= 0.58 {
            mattrComponent = 12 + (mattr - 0.58) / 0.14 * 8
        } else if mattr >= 0.45 {
            mattrComponent = 5 + (mattr - 0.45) / 0.13 * 7
        } else {
            mattrComponent = mattr / 0.45 * 5
        }
        score += mattrComponent

        let densityComponent: Double
        if contentWordDensity >= 22 {
            densityComponent = 20
        } else if contentWordDensity >= 10 {
            densityComponent = 12 + (contentWordDensity - 10) / 12.0 * 8
        } else if contentWordDensity >= 4 {
            densityComponent = 5 + (contentWordDensity - 4) / 6.0 * 7
        } else {
            densityComponent = contentWordDensity / 4.0 * 5
        }
        score += densityComponent

        let mlrComponent: Double
        if mlr >= 10 {
            mlrComponent = 15
        } else if mlr >= 5 {
            mlrComponent = 8 + (mlr - 5) / 5.0 * 7
        } else if mlr >= 2 {
            mlrComponent = (mlr - 2) / 3.0 * 8
        } else {
            mlrComponent = 0
        }
        score += mlrComponent

        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - Fluency Score

    static func computeFluencyScore(
        phonationTimeRatio: Double,
        mlr: Double,
        articulationRate: Double,
        pauseMetadata: [PauseInfo],
        actualDuration: TimeInterval
    ) -> Int {
        var score = 0.0

        let ptrComponent: Double
        if phonationTimeRatio >= 0.45 && phonationTimeRatio <= 0.80 {
            ptrComponent = 35
        } else if phonationTimeRatio >= 0.35 && phonationTimeRatio < 0.45 {
            ptrComponent = 22 + (phonationTimeRatio - 0.35) / 0.10 * 13
        } else if phonationTimeRatio > 0.80 && phonationTimeRatio <= 0.90 {
            ptrComponent = 22 + (0.90 - phonationTimeRatio) / 0.10 * 13
        } else if phonationTimeRatio >= 0.25 && phonationTimeRatio < 0.35 {
            ptrComponent = 8 + (phonationTimeRatio - 0.25) / 0.10 * 14
        } else if phonationTimeRatio > 0.90 {
            ptrComponent = max(10, 22 - (phonationTimeRatio - 0.90) / 0.10 * 12)
        } else {
            ptrComponent = max(0, phonationTimeRatio / 0.25 * 8)
        }
        score += ptrComponent

        let mlrComponent: Double
        if mlr >= 8 {
            mlrComponent = 35
        } else if mlr >= 5 {
            mlrComponent = 22 + (mlr - 5) / 3.0 * 13
        } else if mlr >= 3 {
            mlrComponent = 12 + (mlr - 3) / 2.0 * 10
        } else if mlr >= 1.5 {
            mlrComponent = 4 + (mlr - 1.5) / 1.5 * 8
        } else {
            mlrComponent = max(0, mlr / 1.5 * 4)
        }
        score += mlrComponent

        let articulationComponent: Double
        if articulationRate >= 100 && articulationRate <= 200 {
            articulationComponent = 30
        } else if articulationRate >= 75 && articulationRate < 100 {
            articulationComponent = 20 + (articulationRate - 75) / 25.0 * 10
        } else if articulationRate > 200 && articulationRate <= 240 {
            articulationComponent = 20 + (240 - articulationRate) / 40.0 * 10
        } else if articulationRate >= 50 && articulationRate < 75 {
            articulationComponent = 8 + (articulationRate - 50) / 25.0 * 12
        } else if articulationRate > 240 {
            articulationComponent = max(5, 20 - (articulationRate - 240) / 40.0 * 15)
        } else {
            articulationComponent = max(0, articulationRate / 50.0 * 8)
        }
        score += articulationComponent

        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - Lexical Sophistication Score

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

        let cleaned = words.map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
        let avgWordLength = cleaned.isEmpty ? 0 : Double(cleaned.reduce(0) { $0 + $1.count }) / Double(cleaned.count)
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

        let rarityComponent = computeWordRarityScore(words: cleaned) * 25.0
        score += rarityComponent

        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - MATTR Computation

    static func computeMATTR(words: [TranscriptionWord], windowSize: Int = 50) -> Double {
        let cleaned = words.map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.count >= 2 }

        guard cleaned.count >= 2 else {
            let unique = Set(cleaned).count
            return cleaned.isEmpty ? 0 : Double(unique) / Double(cleaned.count)
        }

        if cleaned.count <= windowSize {
            let unique = Set(cleaned).count
            return Double(unique) / Double(cleaned.count)
        }

        var windowTTRs: [Double] = []
        for i in 0...(cleaned.count - windowSize) {
            let window = cleaned[i..<(i + windowSize)]
            let unique = Set(window).count
            windowTTRs.append(Double(unique) / Double(windowSize))
        }

        return windowTTRs.reduce(0, +) / Double(windowTTRs.count)
    }

    // MARK: - Mean Length of Run

    static func computeMeanLengthOfRun(
        words: [TranscriptionWord],
        pauseMetadata: [PauseInfo]
    ) -> Double {
        guard !words.isEmpty else { return 0 }
        _ = pauseMetadata  // suppress unused parameter warning

        let sorted = words.sorted { $0.start < $1.start }

        var runs: [Int] = []
        var currentRun = 0

        for i in sorted.indices {
            currentRun += 1
            let word = sorted[i]

            let isLastWord = i == sorted.count - 1
            if isLastWord {
                // End of transcript — close the final run
                if currentRun > 0 { runs.append(currentRun) }
                currentRun = 0
            } else {
                let nextWordStart = sorted[i + 1].start
                let gapAfter = nextWordStart - word.end
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

    nonisolated static let gibberishKnownTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb, .pronoun,
                                                              .determiner, .particle, .preposition, .conjunction,
                                                              .interjection, .number]

    static func detectGibberish(
        words: [TranscriptionWord],
        scoringText: String
    ) -> GibberishResult {
        guard !scoringText.isEmpty, !words.isEmpty else {
            return GibberishResult(confidence: 1.0, reason: "No speech detected", isDefinitelyGibberish: true)
        }

        var failedChecks = 0
        var reasons: [String] = []

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

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = scoringText
        var totalTokens = 0
        var recognizedTokens = 0

        tagger.enumerateTags(in: scoringText.startIndex..<scoringText.endIndex,
                              unit: .word, scheme: .lexicalClass) { tag, _ in
            totalTokens += 1
            if let tag, gibberishKnownTags.contains(tag) { recognizedTokens += 1 }
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

    static func computeWordRarityScore(words: [String]) -> Double {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
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
            let rarity = max(0, min(1.0, (minDist - 0.4) / 1.0))
            totalRarity += rarity
            countedWords += 1
        }

        guard countedWords > 0 else { return 0 }
        return totalRarity / Double(countedWords)
    }

    // MARK: - Overall Score with Substance Multiplier

    static func applySubstanceMultiplier(overallScore: Int, substanceScore: Int) -> Int {
        let s = Double(substanceScore)
        let multiplier: Double

        if s <= 10 {
            multiplier = 0.10 + (s / 10.0) * 0.15
        } else if s <= 30 {
            multiplier = 0.25 + ((s - 10) / 20.0) * 0.40
        } else if s <= 50 {
            multiplier = 0.65 + ((s - 30) / 20.0) * 0.23
        } else if s <= 75 {
            multiplier = 0.88 + ((s - 50) / 25.0) * 0.09
        } else {
            multiplier = 0.97 + ((s - 75) / 25.0) * 0.03
        }

        return max(0, min(100, Int(Double(overallScore) * multiplier)))
    }

    // MARK: - Gibberish Score Gate

    static func applyGibberishGate(score: Int, gibberishConfidence: Double) -> Int {
        if gibberishConfidence >= 0.85 {
            // Definitely gibberish — score collapses to ≤8
            return min(score, 8)
        } else if gibberishConfidence >= 0.65 {
            // Very likely gibberish — cap at 15
            return min(score, 15)
        } else if gibberishConfidence >= 0.45 {
            return min(score, 30)
        }
        return score
    }
}

// MARK: - EnhancedSpeechMetrics

nonisolated struct EnhancedSpeechMetrics: Codable, Equatable {
    var phonationTimeRatio: Double

    var articulationRate: Double

    var meanLengthOfRun: Double

    var mattr: Double

    var contentWordDensity: Double

    var substanceScore: Int

    var fluencyScore: Int

    var lexicalSophisticationScore: Int

    var gibberishConfidence: Double

    var gibberishReason: String?

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

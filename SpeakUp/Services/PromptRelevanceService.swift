import Foundation
import NaturalLanguage

enum PromptRelevanceService {

    // MARK: - Public API

    /// Score how relevant the transcript is to the given prompt (0-100).
    /// Uses keyword overlap + word-level semantic + sentence-level alignment.
    static func score(promptText: String, transcript: String) -> Int? {
        let promptKeywords = extractContentWords(from: promptText)
        let transcriptKeywords = extractContentWords(from: transcript, limit: 100)

        guard promptKeywords.count >= 2, transcriptKeywords.count >= 3 else { return nil }

        let keywordOverlap = computeKeywordOverlap(promptKeywords: promptKeywords, transcriptKeywords: transcriptKeywords)
        let wordSemantic = computeSemanticSimilarity(promptKeywords: promptKeywords, transcriptKeywords: transcriptKeywords)

        // Sentence-level prompt alignment
        let sentenceAlignment = computeSentenceAlignment(promptText: promptText, transcript: transcript)

        var raw: Double
        if let sentAlign = sentenceAlignment, let wordSem = wordSemantic {
            // Full 3-signal scoring
            raw = keywordOverlap * 0.25 + wordSem * 0.35 + sentAlign * 0.40
        } else if let wordSem = wordSemantic {
            // Fallback: no sentence embedding — weight word semantics more heavily
            raw = keywordOverlap * 0.35 + wordSem * 0.65
        } else {
            raw = keywordOverlap
        }

        // Compute coherence once (expensive NLEmbedding work)
        let coherence = coherenceScore(transcript: transcript)

        // Topic consistency bonus: if the transcript is internally coherent,
        // the speech is likely on-topic regardless of keyword overlap.
        if let coherence, coherence > 50 {
            let bonus = coherence > 70 ? 0.20 : 0.12
            raw = min(1.0, raw + bonus)
        }

        // Floor: a coherent speech of substantial length given a prompt
        // should score at least 30
        let transcriptWords = transcript.split(separator: " ").count
        if transcriptWords >= 50, raw < 0.30 {
            if let coherence, coherence > 65 {
                raw = max(raw, 0.30)
            }
        }

        return max(0, min(100, Int(raw * 100)))
    }

    /// Compute a coherence score for free-practice sessions (no prompt).
    /// Multi-signal approach: entity continuity, sentence flow, sliding window
    /// topic drift, weighted discourse markers, and structural progression.
    static func coherenceScore(transcript: String) -> Int? {
        let sentences = splitIntoSentences(transcript)
        guard sentences.count >= 2 else { return nil }

        // Gibberish detection: cap coherence for gibberish
        let wordCounts = sentences.map { $0.split(separator: " ").count }
        let avgSentenceWordCount = Double(wordCounts.reduce(0, +)) / Double(wordCounts.count)

        if avgSentenceWordCount < 3 && sentences.count > 3 {
            return min(20, Int(avgSentenceWordCount * 7))
        }
        if !sentences.contains(where: { $0.split(separator: " ").count > 5 }) {
            return min(30, Int(avgSentenceWordCount * 10))
        }

        // Signal 1: Entity continuity (25%) — do sentences reference the same subjects?
        let entityScore = computeEntityContinuity(sentences: sentences)

        // Signal 2: Adjacent sentence semantic similarity (20%) — with stricter thresholds
        let sentenceFlowScore = computeSentenceFlowScore(sentences: sentences)

        // Signal 3: Sliding window topic drift (20%) — catches mid-speech tangents
        let topicDriftScore = computeSlidingWindowDrift(sentences: sentences)

        // Signal 4: Weighted discourse markers (15%) — quality over quantity
        let connectiveScore = computeWeightedConnectives(sentences: sentences)

        // Signal 5: Structural progression (20%) — intro/body/conclusion arc
        let progressionScore = computeStructuralProgression(sentences: sentences)

        let raw = entityScore * 0.25 +
                  sentenceFlowScore * 0.20 +
                  topicDriftScore * 0.20 +
                  connectiveScore * 0.15 +
                  progressionScore * 0.20
        return max(0, min(100, Int(raw * 100)))
    }

    /// Check if the transcript is likely gibberish.
    static func isLikelyGibberish(transcript: String, words: [TranscriptionWord]) -> Bool {
        guard !transcript.isEmpty else { return true }

        var failedChecks = 0

        // Check 1: Average word confidence < 0.3
        let confidences = words.compactMap { $0.confidence }
        if !confidences.isEmpty {
            let avgConfidence = confidences.reduce(0, +) / Double(confidences.count)
            if avgConfidence < 0.3 {
                failedChecks += 1
            }
        }

        // Check 2: Ratio of real English words via NLTagger
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = transcript
        var totalTokens = 0
        var recognizedTokens = 0
        let knownTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb, .pronoun,
                                      .determiner, .particle, .preposition, .conjunction,
                                      .interjection, .number]

        tagger.enumerateTags(in: transcript.startIndex..<transcript.endIndex, unit: .word, scheme: .lexicalClass) { tag, _ in
            totalTokens += 1
            if let tag, knownTags.contains(tag) {
                recognizedTokens += 1
            }
            return true
        }

        if totalTokens > 0 {
            let recognizedRatio = Double(recognizedTokens) / Double(totalTokens)
            if recognizedRatio < 0.4 {
                failedChecks += 1
            }
        }

        // Check 3: No sentence has > 4 words
        let sentences = splitIntoSentences(transcript)
        let maxSentenceWords = sentences.map { $0.split(separator: " ").count }.max() ?? 0
        if maxSentenceWords <= 4 && sentences.count > 2 {
            failedChecks += 1
        }

        return failedChecks >= 2
    }

    // MARK: - Content Word Extraction

    private static func extractContentWords(from text: String, limit: Int = .max) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text

        var words: [String] = []
        let contentTags: Set<NLTag> = [.noun, .verb, .adjective, .adverb]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            guard words.count < limit else { return false }
            guard let tag, contentTags.contains(tag) else { return true }

            // Get lemma for normalization
            let lemmaTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
            let word = (lemmaTag.0?.rawValue ?? String(text[range])).lowercased()

            // Skip very short words and common stopword verbs
            guard word.count >= 3, !stopVerbs.contains(word) else { return true }

            words.append(word)
            return true
        }

        return words
    }

    // MARK: - Keyword Overlap

    private static func computeKeywordOverlap(promptKeywords: [String], transcriptKeywords: [String]) -> Double {
        let promptSet = Set(promptKeywords)
        let transcriptSet = Set(transcriptKeywords)
        let intersection = promptSet.intersection(transcriptSet)
        return Double(intersection.count) / Double(promptSet.count)
    }

    // MARK: - Semantic Similarity (word-level)

    private static func computeSemanticSimilarity(promptKeywords: [String], transcriptKeywords: [String]) -> Double? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }

        let transcriptSet = Array(Set(transcriptKeywords))
        var totalSim = 0.0
        var counted = 0

        for promptWord in Set(promptKeywords) {
            guard embedding.contains(promptWord) else { continue }

            var bestSim = 0.0
            for transcriptWord in transcriptSet {
                guard embedding.contains(transcriptWord) else { continue }
                let distance = embedding.distance(between: promptWord, and: transcriptWord)
                // NLEmbedding distance is cosine distance (0=identical, 2=opposite)
                // Non-linear scaling: distance < 0.8 is meaningfully related
                let sim = max(0, 1.0 - distance * 0.55)
                bestSim = max(bestSim, sim)
            }

            totalSim += bestSim
            counted += 1
        }

        guard counted > 0 else { return nil }
        return totalSim / Double(counted)
    }

    // MARK: - Sentence-Level Alignment (prompt mode)

    private static func computeSentenceAlignment(promptText: String, transcript: String) -> Double? {
        guard let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }

        let transcriptSentences = splitIntoSentences(transcript)
        guard !transcriptSentences.isEmpty else { return nil }
        guard sentenceEmbedding.contains(promptText) else { return nil }

        var totalSim = 0.0
        var counted = 0

        for sentence in transcriptSentences {
            guard sentenceEmbedding.contains(sentence) else { continue }
            let distance = sentenceEmbedding.distance(between: promptText, and: sentence)
            let sim = max(0, 1.0 - distance * 0.55)
            totalSim += sim
            counted += 1
        }

        guard counted > 0 else { return nil }
        return min(1.0, (totalSim / Double(counted)) * 2.5)
    }

    // MARK: - Coherence Signal 1: Entity Continuity

    /// Tracks nouns and named entities across sentences.
    /// Score = fraction of sentences that share at least one entity with the previous sentence.
    private static func computeEntityContinuity(sentences: [String]) -> Double {
        guard sentences.count >= 2 else { return 1.0 }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        let entityTags: Set<NLTag> = [.noun, .personalName, .placeName, .organizationName]
        // Pronouns indicate back-reference to prior entities
        let pronouns: Set<String> = [
            "he", "she", "it", "they", "him", "her", "them", "his", "hers",
            "its", "their", "this", "that", "these", "those", "who", "which"
        ]

        // Extract entities per sentence
        var sentenceEntities: [Set<String>] = []
        for sentence in sentences {
            tagger.string = sentence
            var entities = Set<String>()
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
                let word = String(sentence[range]).lowercased().trimmingCharacters(in: .punctuationCharacters)
                guard word.count >= 2 else { return true }
                if let tag, entityTags.contains(tag) {
                    entities.insert(word)
                } else if pronouns.contains(word) {
                    entities.insert("__pronoun__")  // Marker: pronoun references prior entity
                }
                return true
            }
            sentenceEntities.append(entities)
        }

        // Score: % of sentences that share entities with prior sentence or use pronouns
        var continuityCount = 0
        for i in 1..<sentenceEntities.count {
            let prev = sentenceEntities[i - 1]
            let curr = sentenceEntities[i]
            let sharedEntities = prev.intersection(curr).subtracting(["__pronoun__"])
            let hasPronounRef = curr.contains("__pronoun__") && !prev.isEmpty
            if !sharedEntities.isEmpty || hasPronounRef {
                continuityCount += 1
            }
        }

        let ratio = Double(continuityCount) / Double(sentences.count - 1)
        // Map: 0% shared = 0.1, 50% = 0.5, 80%+ = 0.9+
        return min(1.0, ratio * 1.15 + 0.1)
    }

    // MARK: - Coherence Signal 2: Sentence Flow (stricter thresholds)

    /// Measures semantic similarity between adjacent sentences.
    /// Uses stricter non-linear mapping than before.
    private static func computeSentenceFlowScore(sentences: [String]) -> Double {
        guard sentences.count >= 2 else { return 1.0 }

        // Try sentence-level embeddings first
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) {
            var totalSim = 0.0
            var pairs = 0

            for i in 0..<(sentences.count - 1) {
                let current = sentences[i]
                let next = sentences[i + 1]
                guard sentenceEmbedding.contains(current), sentenceEmbedding.contains(next) else { continue }

                let distance = sentenceEmbedding.distance(between: current, and: next)
                // Stricter non-linear mapping:
                // distance 0.0-0.5 = high similarity (0.7-1.0)
                // distance 0.5-1.0 = moderate (0.3-0.7)
                // distance 1.0-1.5 = low (0.0-0.3)
                let sim: Double
                if distance < 0.5 {
                    sim = 0.7 + (0.5 - distance) * 0.6
                } else if distance < 1.0 {
                    sim = 0.3 + (1.0 - distance) * 0.8
                } else {
                    sim = max(0, 0.3 - (distance - 1.0) * 0.6)
                }
                totalSim += sim
                pairs += 1
            }

            if pairs > 0 {
                return totalSim / Double(pairs)
            }
        }

        // Fallback: word-level topic consistency
        return computeTopicConsistencyWordLevel(sentences: sentences)
    }

    // MARK: - Coherence Signal 3: Sliding Window Topic Drift

    /// Checks every 3-sentence window for topic drift instead of just first/last/middle.
    private static func computeSlidingWindowDrift(sentences: [String]) -> Double {
        guard sentences.count >= 3 else { return 0.8 }

        let sentenceKeywords = sentences.map { Set(extractContentWords(from: $0)) }
        let windowSize = 3
        var driftViolations = 0
        var totalWindows = 0

        for i in 0...(sentences.count - windowSize) {
            let windowSets = sentenceKeywords[i..<(i + windowSize)]
            totalWindows += 1

            // Check if all sentences in window share any content words
            var allKeywords = Set<String>()
            var pairwiseOverlap = 0
            let windowArray = Array(windowSets)

            for j in 0..<windowArray.count {
                allKeywords.formUnion(windowArray[j])
                if j > 0 {
                    let shared = windowArray[j - 1].intersection(windowArray[j])
                    if !shared.isEmpty { pairwiseOverlap += 1 }
                }
            }

            // Violation: no pairwise overlap in the window = topic jump
            if pairwiseOverlap == 0 && !allKeywords.isEmpty {
                driftViolations += 1
            }
        }

        // Also use sentence embeddings if available for stronger drift detection
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) {
            for i in 0...(sentences.count - windowSize) {
                let first = sentences[i]
                let last = sentences[i + windowSize - 1]
                guard sentenceEmbedding.contains(first), sentenceEmbedding.contains(last) else { continue }
                let dist = sentenceEmbedding.distance(between: first, and: last)
                if dist > 1.4 { // Very different topics within a 3-sentence window
                    driftViolations += 1
                }
            }
        }

        guard totalWindows > 0 else { return 0.8 }
        // Deduplicate: cap violations at totalWindows
        let cappedViolations = min(driftViolations, totalWindows)
        let ratio = Double(cappedViolations) / Double(totalWindows)
        return max(0, 1.0 - ratio)
    }

    // MARK: - Coherence Signal 4: Weighted Discourse Markers

    /// Scores connectives by category weight and sentence-boundary position.
    private static func computeWeightedConnectives(sentences: [String]) -> Double {
        let totalWordCount = sentences.reduce(0) { $0 + $1.split(separator: " ").count }
        guard totalWordCount >= 10 else { return 0.5 }

        // Categories with semantic weights
        let logicalConnectives: Set<String> = ["therefore", "because", "consequently", "thus", "hence", "accordingly"]
        let contrastConnectives: Set<String> = ["however", "although", "nevertheless", "on the other hand", "in contrast"]
        let additiveConnectives: Set<String> = ["also", "furthermore", "moreover", "in addition", "additionally"]
        let sequencingConnectives: Set<String> = ["first", "second", "third", "finally", "next", "then"]
        let commonConnectives: Set<String> = ["and", "but", "so", "yet", "while"]

        var weightedScore = 0.0
        var uniqueCategories = Set<String>()

        for sentence in sentences {
            let lowered = sentence.lowercased()
            // Get first 4 words for sentence-boundary detection
            let firstWords = lowered.split(separator: " ").prefix(4).joined(separator: " ")

            func checkCategory(_ name: String, _ connectives: Set<String>, weight: Double) {
                for conn in connectives {
                    if firstWords.contains(conn) {
                        // Full weight: connective at sentence start
                        weightedScore += weight
                        uniqueCategories.insert(name)
                    } else if lowered.contains(conn) {
                        // Reduced weight: connective mid-sentence
                        weightedScore += weight * 0.3
                        uniqueCategories.insert(name)
                    }
                }
            }

            checkCategory("logical", logicalConnectives, weight: 3.0)
            checkCategory("contrast", contrastConnectives, weight: 2.0)
            checkCategory("additive", additiveConnectives, weight: 2.0)
            checkCategory("sequence", sequencingConnectives, weight: 2.5)
            checkCategory("common", commonConnectives, weight: 0.5)
        }

        // Category variety bonus (using 3+ categories shows structured thinking)
        let varietyBonus = min(0.3, Double(uniqueCategories.count) * 0.08)
        // Normalize weighted score (target: ~8.0 for well-structured speech)
        let normalizedScore = min(1.0, weightedScore / 10.0)

        return min(1.0, normalizedScore * 0.7 + varietyBonus + 0.1)
    }

    // MARK: - Coherence Signal 5: Structural Progression

    /// Checks if the speech has an intro→body→conclusion arc.
    private static func computeStructuralProgression(sentences: [String]) -> Double {
        guard sentences.count >= 3 else { return 0.5 }

        var score = 0.5  // Base: neutral

        // 1. Opening sentence is substantial (>5 words) = has a topic statement
        let openingWords = sentences[0].split(separator: " ").count
        if openingWords >= 5 { score += 0.1 }

        // 2. Closing sentence is substantial = has a conclusion/summary
        let closingWords = sentences[sentences.count - 1].split(separator: " ").count
        if closingWords >= 5 { score += 0.1 }

        // 3. Body sentences (middle) are longer than opening/closing on average
        // = depth/elaboration in the body
        if sentences.count >= 5 {
            let bodyRange = 1..<(sentences.count - 1)
            let bodyLengths = sentences[bodyRange].map { $0.split(separator: " ").count }
            let avgBody = Double(bodyLengths.reduce(0, +)) / Double(bodyLengths.count)
            if avgBody > Double(openingWords) * 0.8 { score += 0.1 }
        }

        // 4. Sentence length variety (not all same length = more natural)
        let lengths = sentences.map { Double($0.split(separator: " ").count) }
        let avgLen = lengths.reduce(0, +) / Double(lengths.count)
        let lengthVariance = lengths.reduce(0.0) { $0 + pow($1 - avgLen, 2) } / Double(lengths.count)
        let lengthCV = avgLen > 0 ? sqrt(lengthVariance) / avgLen : 0
        if lengthCV > 0.3 && lengthCV < 1.0 { score += 0.1 }  // Good variety

        // 5. Last sentence references topics from first sentence (circular closure)
        let firstKeywords = Set(extractContentWords(from: sentences[0]))
        let lastKeywords = Set(extractContentWords(from: sentences[sentences.count - 1]))
        if !firstKeywords.isEmpty && !lastKeywords.isEmpty {
            let overlap = firstKeywords.intersection(lastKeywords)
            if !overlap.isEmpty { score += 0.1 }
        }

        return min(1.0, max(0, score))
    }

    // MARK: - Word-Level Topic Consistency (fallback)

    private static func computeTopicConsistencyWordLevel(sentences: [String]) -> Double {
        guard sentences.count >= 2 else { return 1.0 }

        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return computeJaccardConsistency(sentences: sentences)
        }

        var totalSimilarity = 0.0
        var pairs = 0

        let sentenceKeywords = sentences.map { extractContentWords(from: $0) }

        for i in 0..<(sentenceKeywords.count - 1) {
            let current = sentenceKeywords[i]
            let next = sentenceKeywords[i + 1]
            guard !current.isEmpty, !next.isEmpty else { continue }

            var pairSim = 0.0
            var matches = 0

            for wordA in current {
                guard embedding.contains(wordA) else { continue }
                var bestWordSim = 0.0
                for wordB in next {
                    guard embedding.contains(wordB) else { continue }
                    let dist = embedding.distance(between: wordA, and: wordB)
                    let sim = max(0, 1.0 - dist)
                    bestWordSim = max(bestWordSim, sim)
                }
                pairSim += bestWordSim
                matches += 1
            }

            if matches > 0 {
                totalSimilarity += (pairSim / Double(matches))
                pairs += 1
            }
        }

        guard pairs > 0 else { return 0.5 }
        let avgSim = totalSimilarity / Double(pairs)
        return min(1.0, avgSim * 1.2)  // Stricter scaling (was 1.5)
    }

    private static func computeJaccardConsistency(sentences: [String]) -> Double {
        let sentenceWords = sentences.map { Set(extractContentWords(from: $0)) }
        var totalOverlap = 0.0
        var pairs = 0

        for i in 0..<(sentenceWords.count - 1) {
            let current = sentenceWords[i]
            let next = sentenceWords[i + 1]
            guard !current.isEmpty || !next.isEmpty else { continue }
            let union = current.union(next)
            guard !union.isEmpty else { continue }
            let intersection = current.intersection(next)
            totalOverlap += Double(intersection.count) / Double(union.count)
            pairs += 1
        }

        guard pairs > 0 else { return 0.5 }
        return min(1.0, (totalOverlap / Double(pairs)) * 2.5)  // Stricter (was 3.0)
    }

    // MARK: - Sentence Splitting

    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }

    // MARK: - Constants

    private static let stopVerbs: Set<String> = [
        "be", "is", "am", "are", "was", "were", "been", "being",
        "have", "has", "had", "do", "does", "did",
        "get", "got", "say", "said", "make", "made",
        "can", "could", "will", "would", "shall", "should", "may", "might"
    ]

    static let connectives: [String] = [
        "however", "therefore", "because", "although", "furthermore",
        "moreover", "consequently", "nevertheless", "for example",
        "for instance", "in addition", "on the other hand",
        "in contrast", "as a result", "in conclusion",
        "first", "second", "third", "finally",
        "similarly", "meanwhile", "instead", "otherwise", "specifically",
        "then", "but", "and", "yet", "while", "since", "thus",
        "hence", "accordingly", "rather", "indeed"
    ]
}

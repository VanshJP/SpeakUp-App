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

        // Floor: a coherent speech of reasonable length given a prompt
        // should score at least 40
        let transcriptWords = transcript.split(separator: " ").count
        if transcriptWords >= 30, raw < 0.40 {
            if let coherence, coherence > 40 {
                raw = max(raw, 0.40)
            }
        }

        return max(0, min(100, Int(raw * 100)))
    }

    /// Compute a coherence score for free-practice sessions (no prompt).
    /// Uses sentence flow + topic drift + structural connectives (0-100).
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

        let sentenceFlowScore = computeSentenceFlowScore(sentences: sentences)
        let topicDriftScore = computeTopicDriftScore(sentences: sentences)
        let connectiveScore = computeStructuralConnectives(transcript: transcript)

        let raw = sentenceFlowScore * 0.50 + topicDriftScore * 0.30 + connectiveScore * 0.20
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

    // MARK: - Coherence: Sentence Flow Score

    /// Measures semantic similarity between adjacent sentences using sentence-level embeddings.
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
                let sim = max(0, 1.0 - distance)
                totalSim += sim
                pairs += 1
            }

            if pairs > 0 {
                let avgSim = totalSim / Double(pairs)
                return min(1.0, avgSim * 1.8)
            }
        }

        // Fallback: word-level topic consistency
        return computeTopicConsistencyWordLevel(sentences: sentences)
    }

    // MARK: - Coherence: Topic Drift Score

    /// Measures how much the topic drifts from beginning to end.
    private static func computeTopicDriftScore(sentences: [String]) -> Double {
        guard sentences.count >= 3 else { return 0.8 } // Short speeches don't drift much

        // Try sentence embeddings
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) {
            let first = sentences[0]
            let last = sentences[sentences.count - 1]
            let middleIdx = sentences.count / 2
            let middle = sentences[middleIdx]

            var maxDrift = 0.0

            if sentenceEmbedding.contains(first) {
                if sentenceEmbedding.contains(last) {
                    let d = sentenceEmbedding.distance(between: first, and: last)
                    maxDrift = max(maxDrift, d)
                }
                if sentenceEmbedding.contains(middle) {
                    let d = sentenceEmbedding.distance(between: first, and: middle)
                    maxDrift = max(maxDrift, d)
                }
            }

            if maxDrift > 0 {
                return max(0, 1.0 - maxDrift * 0.8)
            }
        }

        // Fallback: use word-level Jaccard between first and last sentence
        let firstWords = Set(extractContentWords(from: sentences[0]))
        let lastWords = Set(extractContentWords(from: sentences[sentences.count - 1]))
        guard !firstWords.isEmpty || !lastWords.isEmpty else { return 0.5 }
        let union = firstWords.union(lastWords)
        guard !union.isEmpty else { return 0.5 }
        let intersection = firstWords.intersection(lastWords)
        let jaccard = Double(intersection.count) / Double(union.count)
        return min(1.0, jaccard * 3.0)
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
        return min(1.0, avgSim * 1.5)
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
        return min(1.0, (totalOverlap / Double(pairs)) * 3.0)
    }

    // MARK: - Structural Connectives

    private static func computeStructuralConnectives(transcript: String) -> Double {
        let text = transcript.lowercased()
        let words = text.split(separator: " ")
        guard words.count >= 10 else { return 0.5 }

        var foundConnectives = Set<String>()
        var totalFound = 0

        for connective in connectives {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: connective))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matchCount = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
                if matchCount > 0 {
                    foundConnectives.insert(connective)
                    totalFound += matchCount
                }
            }
        }

        let varietyScore = min(1.0, Double(foundConnectives.count) / 6.0)
        let frequencyScore = min(1.0, Double(totalFound) / 8.0)

        return (varietyScore * 0.7) + (frequencyScore * 0.3)
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

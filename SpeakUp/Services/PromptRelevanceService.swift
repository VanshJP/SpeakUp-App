import Foundation
import NaturalLanguage

enum PromptRelevanceService {

    // MARK: - Public API

    /// Score how relevant the transcript is to the given prompt (0-100).
    /// Returns nil if inputs are too short or embedding is unavailable.
    static func score(promptText: String, transcript: String) -> Int? {
        let promptKeywords = extractContentWords(from: promptText)
        let transcriptKeywords = extractContentWords(from: transcript, limit: 100)

        guard promptKeywords.count >= 2, transcriptKeywords.count >= 3 else { return nil }

        let keywordOverlap = computeKeywordOverlap(promptKeywords: promptKeywords, transcriptKeywords: transcriptKeywords)
        let semanticSimilarity = computeSemanticSimilarity(promptKeywords: promptKeywords, transcriptKeywords: transcriptKeywords)

        let raw: Double
        if let semantic = semanticSimilarity {
            raw = keywordOverlap * 0.4 + semantic * 0.6
        } else {
            raw = keywordOverlap
        }

        return max(0, min(100, Int(raw * 100)))
    }

    /// Compute a coherence score for free-practice sessions (no prompt).
    /// Measures topic consistency and argument structure (0-100).
    /// Returns nil if transcript is too short.
    static func coherenceScore(transcript: String) -> Int? {
        let sentences = splitIntoSentences(transcript)
        guard sentences.count >= 2 else { return nil }

        let topicConsistency = computeTopicConsistency(sentences: sentences)
        let structureRatio = computeStructuralConnectives(transcript: transcript)

        let raw = topicConsistency * 0.5 + structureRatio * 0.5
        return max(0, min(100, Int(raw * 100)))
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

    // MARK: - Semantic Similarity

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
                let sim = max(0, 1.0 - distance)
                bestSim = max(bestSim, sim)
            }

            totalSim += bestSim
            counted += 1
        }

        guard counted > 0 else { return nil }
        return totalSim / Double(counted)
    }

    // MARK: - Coherence Helpers

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

    private static func computeTopicConsistency(sentences: [String]) -> Double {
        guard sentences.count >= 2 else { return 1.0 }

        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            // Fallback to Jaccard if embedding is unavailable
            return computeJaccardConsistency(sentences: sentences)
        }

        var totalSimilarity = 0.0
        var pairs = 0

        let sentenceKeywords = sentences.map { extractContentWords(from: $0) }

        for i in 0..<(sentenceKeywords.count - 1) {
            let current = sentenceKeywords[i]
            let next = sentenceKeywords[i + 1]
            guard !current.isEmpty, !next.isEmpty else { continue }

            // Compute similarity between current and next sentence
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
        
        // Semantic similarity of 0.3-0.5 between adjacent sentences is actually quite strong
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

    private static func computeStructuralConnectives(transcript: String) -> Double {
        let text = transcript.lowercased()
        let words = text.split(separator: " ")
        guard words.count >= 10 else { return 0.5 }

        var foundConnectives = Set<String>()
        var totalFound = 0

        for connective in connectives {
            // Use word boundary check to avoid partial matches (e.g., "so" in "soon")
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: connective))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matchCount = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
                if matchCount > 0 {
                    foundConnectives.insert(connective)
                    totalFound += matchCount
                }
            }
        }

        // Scoring: Reward both variety and presence
        // 6+ unique connectives or 8+ total usages is a great score
        let varietyScore = min(1.0, Double(foundConnectives.count) / 6.0)
        let frequencyScore = min(1.0, Double(totalFound) / 8.0)
        
        return (varietyScore * 0.7) + (frequencyScore * 0.3)
    }

    // MARK: - Constants

    private static let stopVerbs: Set<String> = [
        "be", "is", "am", "are", "was", "were", "been", "being",
        "have", "has", "had", "do", "does", "did",
        "get", "got", "say", "said", "make", "made",
        "can", "could", "will", "would", "shall", "should", "may", "might"
    ]

    private static let connectives: [String] = [
        // Logical/Formal transitions
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

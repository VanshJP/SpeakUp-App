import Foundation
import NaturalLanguage

/// On-device text quality analysis for speech transcripts.
/// Detects hedge words, power words, rhetorical devices, and transition variety.
/// Uses only Apple NaturalLanguage framework — no external dependencies.
enum TextAnalysisService {

    // MARK: - Public API

    /// Analyze text quality metrics from a transcript.
    static func analyze(text: String, totalWords: Int) -> TextQualityMetrics {
        guard !text.isEmpty, totalWords > 0 else { return TextQualityMetrics() }

        let lowered = text.lowercased()
        let words = lowered.split(separator: " ").map { String($0).trimmingCharacters(in: .punctuationCharacters) }

        let hedgeCount = countHedgeWords(in: words)
        let hedgeRatio = Double(hedgeCount) / Double(totalWords)
        let powerCount = countPowerWords(in: words)
        let rhetoricalCount = countRhetoricalDevices(text: lowered, words: words)
        let transitionVariety = countTransitionVariety(in: lowered)

        // Authority score: penalize hedges, reward power words
        // Base 70, -3 per hedge word (max -30), +5 per power word (max +30)
        let hedgePenalty = min(30, hedgeCount * 3)
        let powerBonus = min(30, powerCount * 5)
        let authorityScore = max(0, min(100, 70 - hedgePenalty + powerBonus))

        // Craft score: reward rhetorical devices and transition variety
        // Base 40, +10 per rhetorical device (max +30), +5 per unique transition (max +30)
        let deviceBonus = min(30, rhetoricalCount * 10)
        let transitionBonus = min(30, transitionVariety * 5)
        let craftScore = max(0, min(100, 40 + deviceBonus + transitionBonus))

        return TextQualityMetrics(
            hedgeWordCount: hedgeCount,
            hedgeWordRatio: hedgeRatio,
            powerWordCount: powerCount,
            rhetoricalDeviceCount: rhetoricalCount,
            transitionVariety: transitionVariety,
            authorityScore: authorityScore,
            craftScore: craftScore
        )
    }

    // MARK: - Hedge Words

    /// Words/phrases that weaken authority and conviction.
    private static let hedgeWords: Set<String> = [
        "maybe", "perhaps", "possibly", "probably", "somewhat",
        "apparently", "arguably", "supposedly", "seemingly"
    ]

    /// Multi-word hedge phrases.
    private static let hedgePhrases: [String] = [
        "i think", "i guess", "i suppose", "i believe",
        "sort of", "kind of", "more or less", "in a way",
        "to some extent", "it seems like", "i feel like",
        "not really sure", "i'm not sure", "if you will",
        "you could say", "in my opinion"
    ]

    private static func countHedgeWords(in words: [String]) -> Int {
        var count = 0

        // Single hedge words
        for word in words {
            if hedgeWords.contains(word) {
                count += 1
            }
        }

        // Multi-word hedge phrases
        let joined = words.joined(separator: " ")
        for phrase in hedgePhrases {
            var searchRange = joined.startIndex..<joined.endIndex
            while let range = joined.range(of: phrase, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<joined.endIndex
            }
        }

        return count
    }

    // MARK: - Power Words

    /// Words that convey confidence, authority, and impact.
    private static let powerWords: Set<String> = [
        // Authority & certainty
        "absolutely", "certainly", "clearly", "definitely", "undoubtedly",
        "precisely", "exactly", "fundamentally", "unquestionably",
        // Impact & urgency
        "critical", "crucial", "essential", "vital", "imperative",
        "urgent", "significant", "remarkable", "extraordinary", "exceptional",
        // Transformation
        "transform", "revolutionize", "breakthrough", "innovate", "pioneer",
        "empower", "inspire", "overcome", "achieve", "accomplish",
        // Evidence & conviction
        "proven", "demonstrated", "evidence", "research", "data",
        "results", "impact", "measurable", "tangible", "concrete",
        // Emotional resonance
        "powerful", "compelling", "profound", "meaningful", "passionate"
    ]

    private static func countPowerWords(in words: [String]) -> Int {
        words.filter { powerWords.contains($0) }.count
    }

    // MARK: - Rhetorical Devices

    private static func countRhetoricalDevices(text: String, words: [String]) -> Int {
        var count = 0
        count += detectTricolon(in: text)
        count += detectAnaphora(in: text)
        count += detectContrast(in: text)
        return count
    }

    /// Rule of Three (Tricolon): "X, Y, and Z" pattern
    /// E.g., "life, liberty, and the pursuit of happiness"
    private static func detectTricolon(in text: String) -> Int {
        // Pattern: "word, word, and word" or "word, word and word"
        let pattern = "\\b\\w+,\\s+\\w+,?\\s+and\\s+\\w+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Anaphora: repeated words/phrases at the start of consecutive sentences/clauses.
    /// E.g., "We will fight... We will never... We will always..."
    private static func detectAnaphora(in text: String) -> Int {
        let sentences = splitSentences(text)
        guard sentences.count >= 3 else { return 0 }

        var anaphoraCount = 0
        var consecutiveMatches = 1

        for i in 1..<sentences.count {
            let prevStart = firstNWords(sentences[i - 1], n: 3)
            let currStart = firstNWords(sentences[i], n: 3)

            if !prevStart.isEmpty && prevStart == currStart {
                consecutiveMatches += 1
            } else {
                if consecutiveMatches >= 3 {
                    anaphoraCount += 1
                }
                consecutiveMatches = 1
            }
        }
        if consecutiveMatches >= 3 {
            anaphoraCount += 1
        }

        return anaphoraCount
    }

    /// Contrast/Antithesis: "not X but Y", "instead of X", "rather than X"
    private static func detectContrast(in text: String) -> Int {
        let patterns = [
            "\\bnot\\s+\\w+\\s+but\\s+\\w+",
            "\\binstead of\\b",
            "\\brather than\\b",
            "\\bon one hand\\b.*\\bon the other hand\\b"
        ]
        var total = 0
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            total += regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        return total
    }

    // MARK: - Transition Variety

    private static let transitions: [String] = [
        "however", "therefore", "because", "although", "furthermore",
        "moreover", "consequently", "nevertheless", "for example",
        "for instance", "in addition", "on the other hand",
        "in contrast", "as a result", "in conclusion",
        "first", "second", "third", "finally",
        "similarly", "meanwhile", "instead", "otherwise", "specifically",
        "then", "but", "yet", "while", "since", "thus",
        "hence", "accordingly", "rather", "indeed", "next",
        "additionally", "equally", "notably", "importantly"
    ]

    private static func countTransitionVariety(in text: String) -> Int {
        var found = Set<String>()
        for transition in transitions {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: transition))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                found.insert(transition)
            }
        }
        return found.count
    }

    // MARK: - Helpers

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        return sentences
    }

    private static func firstNWords(_ sentence: String, n: Int) -> String {
        let words = sentence.lowercased().split(separator: " ").prefix(n)
        return words.joined(separator: " ")
    }
}

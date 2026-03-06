import Foundation
import NaturalLanguage

/// On-device text quality analysis for speech transcripts.
/// Detects hedge words, power words, rhetorical devices, and transition variety.
/// Uses only Apple NaturalLanguage framework — no external dependencies.
enum TextAnalysisService {

    // MARK: - Public API

    static func analyze(text: String, totalWords: Int) -> TextQualityMetrics {
        guard !text.isEmpty, totalWords > 0 else { return TextQualityMetrics() }

        let lowered = text.lowercased()
        let words = lowered.split(separator: " ").map { String($0).trimmingCharacters(in: .punctuationCharacters) }

        let hedgeCount = countHedgeWords(in: words)
        let hedgeRatio = Double(hedgeCount) / Double(totalWords)
        let powerCount = countPowerWords(in: words)
        let rhetoricalCount = countRhetoricalDevices(text: lowered, words: words)
        let transitionVariety = countTransitionVariety(in: lowered)

        let hedgePenalty = min(30, hedgeCount * 3)
        let powerBonus = min(30, powerCount * 5)
        let authorityScore = max(0, min(100, 70 - hedgePenalty + powerBonus))

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

    private static let hedgeWords: Set<String> = [
        "maybe", "perhaps", "possibly", "probably", "somewhat",
        "apparently", "arguably", "supposedly", "seemingly"
    ]

    private static let hedgePhrases: [String] = [
        "i think", "i guess", "i suppose", "i believe",
        "sort of", "kind of", "more or less", "in a way",
        "to some extent", "it seems like", "i feel like",
        "not really sure", "i'm not sure", "if you will",
        "you could say", "in my opinion"
    ]

    private static func countHedgeWords(in words: [String]) -> Int {
        var count = 0
        for word in words {
            if hedgeWords.contains(word) { count += 1 }
        }
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

    private static let powerWords: Set<String> = [
        "absolutely", "certainly", "clearly", "definitely", "undoubtedly",
        "precisely", "exactly", "fundamentally", "unquestionably",
        "critical", "crucial", "essential", "vital", "imperative",
        "urgent", "significant", "remarkable", "extraordinary", "exceptional",
        "transform", "revolutionize", "breakthrough", "innovate", "pioneer",
        "empower", "inspire", "overcome", "achieve", "accomplish",
        "proven", "demonstrated", "evidence", "research", "data",
        "results", "impact", "measurable", "tangible", "concrete",
        "powerful", "compelling", "profound", "meaningful", "passionate"
    ]

    private static func countPowerWords(in words: [String]) -> Int {
        words.filter { powerWords.contains($0) }.count
    }

    // MARK: - Rhetorical Devices

    private static func countRhetoricalDevices(text: String, words: [String]) -> Int {
        detectTricolon(in: text) + detectAnaphora(in: text) + detectContrast(in: text)
    }

    private static func detectTricolon(in text: String) -> Int {
        let pattern = "\\b\\w+,\\s+\\w+,?\\s+and\\s+\\w+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

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
                if consecutiveMatches >= 3 { anaphoraCount += 1 }
                consecutiveMatches = 1
            }
        }
        if consecutiveMatches >= 3 { anaphoraCount += 1 }
        return anaphoraCount
    }

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

    private static func firstNWords(_ text: String, n: Int) -> String {
        let words = text.split(separator: " ").prefix(n)
        return words.joined(separator: " ").lowercased()
    }
}

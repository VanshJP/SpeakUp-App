import Foundation

struct ScriptPracticeInsight {
    let adherenceScore: Int
    let matchedWordCount: Int
    let scriptWordCount: Int
    let missedKeywords: [String]
    let offScriptTerms: [String]
}

enum ScriptPracticeAnalyzer {
    static func analyze(script: String, transcript: String) -> ScriptPracticeInsight? {
        let scriptTokens = tokenize(script)
        let transcriptTokens = tokenize(transcript)
        guard !scriptTokens.isEmpty, !transcriptTokens.isEmpty else { return nil }

        // Keep matching bounded for predictable performance on large scripts.
        let cappedScript = Array(scriptTokens.prefix(350))
        let cappedTranscript = Array(transcriptTokens.prefix(350))

        let matched = lcsLength(cappedScript, cappedTranscript)
        let adherence = max(0, min(100, Int((Double(matched) / Double(cappedScript.count)) * 100)))

        let scriptSet = Set(cappedScript)
        let transcriptSet = Set(cappedTranscript)

        let missedKeywords = topKeywords(from: cappedScript, limit: 12).filter { !transcriptSet.contains($0) }
        let offScriptTerms = topKeywords(from: cappedTranscript.filter { !scriptSet.contains($0) }, limit: 8)

        return ScriptPracticeInsight(
            adherenceScore: adherence,
            matchedWordCount: matched,
            scriptWordCount: cappedScript.count,
            missedKeywords: Array(missedKeywords.prefix(5)),
            offScriptTerms: Array(offScriptTerms.prefix(5))
        )
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count >= 2 && !stopWords.contains(token)
            }
    }

    private static func topKeywords(from tokens: [String], limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)
    }

    // Two-row LCS DP to stay memory-safe.
    private static func lcsLength(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

        var previous = Array(repeating: 0, count: rhs.count + 1)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            for j in 1...rhs.count {
                if lhs[i - 1] == rhs[j - 1] {
                    current[j] = previous[j - 1] + 1
                } else {
                    current[j] = max(previous[j], current[j - 1])
                }
            }
            swap(&previous, &current)
        }

        return previous[rhs.count]
    }

    private static let stopWords: Set<String> = [
        "the", "and", "that", "with", "for", "are", "you", "your", "was", "were", "this", "have",
        "from", "they", "their", "about", "just", "there", "would", "could", "into", "than", "then",
        "them", "what", "when", "where", "while", "also", "been", "because", "over", "under", "after",
        "before", "very", "more", "most", "some", "such", "only", "like", "know", "really", "will",
        "shall", "might", "must", "should", "can", "did", "does", "doing", "our", "out", "who", "why"
    ]
}

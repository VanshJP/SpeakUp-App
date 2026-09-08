import Foundation

/// Shared inflection-aware matching for tracked vocab and the daily word workout.
/// Extracted from `SpeechService` so challenge evaluation and transcript
/// highlighting use one regex.
nonisolated enum VocabMatcher {
    static func usages(in text: String, vocabWords: [String]) -> [VocabWordUsage] {
        guard !vocabWords.isEmpty, !text.isEmpty else { return [] }

        let lowercasedText = text.lowercased()
        var results: [VocabWordUsage] = []

        for vocabWord in vocabWords {
            let pattern = inflectedPattern(for: vocabWord)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let count = regex.numberOfMatches(in: lowercasedText, range: NSRange(lowercasedText.startIndex..., in: lowercasedText))
            if count > 0 {
                results.append(VocabWordUsage(word: vocabWord, count: count))
            }
        }

        return results.sorted { $0.count > $1.count }
    }

    static func mark(_ words: [TranscriptionWord], vocabWords: [String]) -> [TranscriptionWord] {
        guard !vocabWords.isEmpty else { return words }

        let regexes: [(String, NSRegularExpression)] = vocabWords.compactMap { vocab in
            let pattern = inflectedPattern(for: vocab)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return (vocab, regex)
        }

        return words.map { word in
            let cleaned = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            let matched = regexes.contains { _, regex in
                regex.firstMatch(in: cleaned, range: range) != nil
            }
            guard matched else { return word }
            return TranscriptionWord(
                word: word.word,
                start: word.start,
                end: word.end,
                confidence: word.confidence,
                isFiller: word.isFiller,
                isVocabWord: true,
                isPrimarySpeaker: word.isPrimarySpeaker,
                speakerConfidence: word.speakerConfidence
            )
        }
    }

    static func contains(_ word: String, in text: String) -> Bool {
        count(of: word, in: text) > 0
    }

    static func count(of word: String, in text: String) -> Int {
        usages(in: text, vocabWords: [word]).first?.count ?? 0
    }

    static func mergeUnique(_ lists: [String]...) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for list in lists {
            for word in list {
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if seen.insert(key).inserted {
                    unique.append(trimmed)
                }
            }
        }
        return unique
    }

    /// Build a regex that matches a word and its common English inflections
    /// (plurals, past tense, progressive, comparative, adverb forms, etc.)
    static func inflectedPattern(for word: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        var alternatives: [String] = []

        // 1. Exact word + directly appended suffixes (e.g. "talk" → "talks", "talked", "talking")
        alternatives.append("\(escaped)(s|es|ed|d|ing|er|ers|est|ly)?")

        // 2. Words ending in 'e': drop 'e' before vowel-starting suffixes
        //    e.g. "create" → "creating", "created", "creative"
        if word.hasSuffix("e") {
            let stem = NSRegularExpression.escapedPattern(for: String(word.dropLast()))
            alternatives.append("\(stem)(ed|ing|er|ers|est|ive|ion|ation|y|ly)")
        }

        // 3. Words ending in consonant + 'y': change 'y' → 'i' before suffixes
        //    e.g. "happy" → "happier", "happiest", "happily", "happiness"
        if word.hasSuffix("y"), word.count > 1 {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let beforeY = word[word.index(word.endIndex, offsetBy: -2)]
            if !vowels.contains(beforeY) {
                let stem = NSRegularExpression.escapedPattern(for: String(word.dropLast()))
                alternatives.append("\(stem)i(es|ed|er|ier|est|iest|ly|ness)")
            }
        }

        // 4. CVC consonant doubling before vowel-starting suffixes
        //    e.g. "run" → "running", "runner"; "big" → "bigger", "biggest"
        let chars = Array(word.lowercased())
        if chars.count >= 3 {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let last = chars[chars.count - 1]
            let secondLast = chars[chars.count - 2]
            let thirdLast = chars[chars.count - 3]
            let noDouble: Set<Character> = ["w", "x", "y"]
            if !vowels.contains(last) && vowels.contains(secondLast) && !vowels.contains(thirdLast) && !noDouble.contains(last) {
                let doubled = escaped + NSRegularExpression.escapedPattern(for: String(last))
                alternatives.append("\(doubled)(ing|ed|er|ers|est)")
            }
        }

        return "\\b(\(alternatives.joined(separator: "|")))\\b"
    }
}

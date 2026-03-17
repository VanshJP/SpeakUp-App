import Foundation

// MARK: - Filler Word Config

/// User-customizable filler word configuration.
struct FillerWordConfig: Sendable {
    let customFillers: Set<String>        // user-added always-detected fillers
    let customContextFillers: Set<String> // user-added context-dependent fillers (pauseBefore && pauseAfter)
    let removedDefaults: Set<String>      // default fillers the user disabled

    nonisolated(unsafe) static let `default` = FillerWordConfig(customFillers: [], customContextFillers: [], removedDefaults: [])

    /// All fillers that should actually be detected, given user customizations.
    var effectiveUnconditionalFillers: Set<String> {
        FillerWordList.unconditionalFillers
            .subtracting(removedDefaults)
            .union(customFillers)
    }

    var effectiveContextDependentFillers: Set<String> {
        FillerWordList.contextDependentFillers
            .subtracting(removedDefaults)
            .union(customContextFillers)
    }

    /// Combined active fillers (unconditional + context-dependent, minus removed).
    var allDefaultFillers: Set<String> {
        FillerWordList.unconditionalFillers.union(FillerWordList.contextDependentFillers)
    }
}

// MARK: - Filler Words List

struct FillerWordList {
    // Words that are ALWAYS fillers (hesitation sounds)
    // Includes variations that Whisper might transcribe
    static let unconditionalFillers: Set<String> = [
        "um", "umm", "ummm", "ummmm", "hum",
        "uh", "uhh", "uhhh", "uhhhh",
        "er", "err", "errr",
        "ah", "ahh", "ahhh",
        "eh", "ehh",
        "oh", "ohh",  // when used as hesitation
        "mm", "mmm", "mhm", "mmhmm", "mm-hmm",
        "hmm", "hmmm", "hmmmm",
        "huh",
        "erm",
        "yeah", "yea",
        "mhmm", "uh-huh", "uhuh"
    ]

    // Words that require context to determine if they're fillers
    static let contextDependentFillers: Set<String> = [
        "like", "so", "just", "well", "right", "okay",
        "actually", "basically", "literally", "honestly", "seriously"
    ]

    // Multi-word filler phrases
    static let fillerPhrases: Set<String> = [
        "you know", "i mean", "sort of", "kind of"
    ]

    // Words that typically precede verbs (non-filler context for "like")
    private static let verbPreceders: Set<String> = [
        "would", "do", "does", "did", "don't", "doesn't", "didn't",
        "i", "you", "we", "they", "he", "she", "it",
        "really", "actually", "also", "always", "never"
    ]

    // Linking verbs that often precede quotative "like"
    private static let linkingVerbs: Set<String> = [
        "was", "is", "are", "were", "be", "been", "being",
        "felt", "looked", "seemed", "acted"
    ]

    // Common adjectives/adverbs that follow filler "like"
    private static let fillerFollowers: Set<String> = [
        "really", "totally", "super", "very", "so", "pretty",
        "kind", "sort", "completely", "absolutely", "honestly"
    ]

    /// Simple check - use for backward compatibility or when context isn't available
    static func isFillerWord(_ word: String) -> Bool {
        let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Unconditional fillers always match
        if unconditionalFillers.contains(lowercased) {
            return true
        }

        // Check for repeated characters (e.g., "ummmmm" -> "um")
        let collapsed = collapseRepeatedChars(lowercased)
        if unconditionalFillers.contains(collapsed) {
            return true
        }

        // Context-dependent words default to false without context
        return false
    }

    /// Context-aware filler detection - preferred method
    static func isFillerWord(
        _ word: String,
        previousWord: String?,
        nextWord: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool = false
    ) -> Bool {
        let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Unconditional fillers always match
        if unconditionalFillers.contains(w) || unconditionalFillers.contains(collapseRepeatedChars(w)) {
            return true
        }

        // Context-dependent words need analysis
        if contextDependentFillers.contains(w) {
            return isContextualFiller(
                word: w,
                prev: previousWord?.lowercased().trimmingCharacters(in: .punctuationCharacters),
                next: nextWord?.lowercased().trimmingCharacters(in: .punctuationCharacters),
                pauseBefore: pauseBefore,
                pauseAfter: pauseAfter,
                isStartOfSentence: isStartOfSentence
            )
        }

        return false
    }

    /// Check if two consecutive words form a filler phrase
    static func isFillerPhrase(_ word1: String, _ word2: String) -> Bool {
        let phrase = "\(word1.lowercased()) \(word2.lowercased())"
        return fillerPhrases.contains(phrase)
    }

    // MARK: - Private Helpers

    private static func isContextualFiller(
        word: String,
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        switch word {
        case "like":
            return isLikeFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        case "so":
            return isSoFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        case "just":
            return isJustFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter)
        case "well":
            return isWellFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        case "right", "okay":
            return isRightOkayFiller(prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter)
        case "actually", "basically", "literally", "honestly", "seriously":
            return isAdverbFiller(word: word, prev: prev, next: next, pauseBefore: pauseBefore, pauseAfter: pauseAfter, isStartOfSentence: isStartOfSentence)
        default:
            // Default: surrounded by pauses = likely filler
            return pauseBefore && pauseAfter
        }
    }

    /// Detect "like" as filler vs verb/preposition
    private static func isLikeFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial "Like, ..." is almost always filler
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Pattern 2: "was/is like" (quotative) - "She was like, 'no way'"
        if let p = prev, linkingVerbs.contains(p) {
            return true
        }

        // Pattern 3: Surrounded by pauses - "I was, like, confused"
        if pauseBefore && pauseAfter {
            return true
        }

        // Pattern 4: Before filler-typical words - "like totally", "like really"
        if let n = next, fillerFollowers.contains(n) {
            return true
        }

        // Anti-pattern 1: After modal/auxiliary - "would like", "do like"
        if let p = prev, verbPreceders.contains(p) {
            return false
        }

        // Anti-pattern 2: Comparative "like" - typically no pauses
        // "runs like the wind", "looks like rain"
        if !pauseBefore && !pauseAfter {
            return false
        }

        // Default: single pause suggests possible filler
        return pauseBefore || pauseAfter
    }

    /// Detect "so" as filler vs intensifier/conjunction
    private static func isSoFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial with pause - "So, anyway..."
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Anti-pattern 1: Intensifier - "so good", "so much", "not so"
        if let p = prev, p == "not" {
            return false
        }

        // Anti-pattern 2: Before adjective without pause (intensifier)
        if !pauseAfter && next != nil {
            return false
        }

        // Surrounded by pauses = filler
        return pauseBefore && pauseAfter
    }

    /// Detect "just" as filler vs adverb
    private static func isJustFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {
        // "just" as filler is typically pause-surrounded and adds no meaning
        // "I, just, don't know" vs "I just arrived" (timing)

        // Surrounded by pauses = likely filler
        if pauseBefore && pauseAfter {
            return true
        }

        // Without pauses, "just" is usually meaningful
        return false
    }

    /// Detect "well" as filler vs adverb
    private static func isWellFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial "Well, ..." is typically filler
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Anti-pattern: "very well", "quite well", "as well"
        if let p = prev, ["very", "quite", "as", "pretty", "really"].contains(p) {
            return false
        }

        // Anti-pattern: "well done", "well made"
        if let n = next, ["done", "made", "known", "written", "said"].contains(n) {
            return false
        }

        return pauseBefore && pauseAfter
    }

    /// Detect "right"/"okay" as fillers (seeking confirmation vs adjective)
    private static func isRightOkayFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {
        // "right?" and "okay?" at end of sentences are confirmation-seeking fillers
        // "the right way" is not a filler

        // Anti-pattern: Article before = adjective ("the right answer")
        if let p = prev, ["the", "a", "an", "that", "this"].contains(p) {
            return false
        }

        // Surrounded by pauses or sentence-final = likely filler
        return pauseBefore || pauseAfter
    }

    /// Detect adverbs like "actually", "basically" as fillers
    private static func isAdverbFiller(
        word: String,
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Sentence-initial with pause = filler
        // "Actually, I think..." vs "I actually think..."
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Mid-sentence surrounded by pauses = filler
        if pauseBefore && pauseAfter {
            return true
        }

        // Without pauses, these usually modify the following word meaningfully
        return false
    }

    private static func collapseRepeatedChars(_ word: String) -> String {
        var result = ""
        var prev: Character?
        for char in word {
            if char != prev {
                result.append(char)
                prev = char
            }
        }
        return result
    }

    // MARK: - Config-Aware Detection

    /// Simple check with user config — for context-dependent custom fillers, defaults to false (needs context).
    static func isFillerWord(_ word: String, config: FillerWordConfig) -> Bool {
        let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let collapsed = collapseRepeatedChars(lowercased)

        // Removed by user — never match
        if config.removedDefaults.contains(lowercased) || config.removedDefaults.contains(collapsed) {
            return false
        }

        // Custom always-detected fillers
        if config.customFillers.contains(lowercased) || config.customFillers.contains(collapsed) {
            return true
        }

        // Unconditional defaults
        if unconditionalFillers.contains(lowercased) || unconditionalFillers.contains(collapsed) {
            return true
        }

        // Custom context fillers — false without context (same as default context-dependent behavior)
        return false
    }

    /// Context-aware filler detection with user config.
    static func isFillerWord(
        _ word: String,
        previousWord: String?,
        nextWord: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool = false,
        config: FillerWordConfig
    ) -> Bool {
        let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let collapsed = collapseRepeatedChars(w)

        // Removed by user — never match
        if config.removedDefaults.contains(w) || config.removedDefaults.contains(collapsed) {
            return false
        }

        // Custom always-detected fillers
        if config.customFillers.contains(w) || config.customFillers.contains(collapsed) {
            return true
        }

        // Unconditional defaults
        if unconditionalFillers.contains(w) || unconditionalFillers.contains(collapsed) {
            return true
        }

        // Custom context-dependent fillers — use simple pause rule
        if config.customContextFillers.contains(w) || config.customContextFillers.contains(collapsed) {
            return pauseBefore && pauseAfter
        }

        // Default context-dependent (only if not removed)
        if contextDependentFillers.contains(w) {
            return isContextualFiller(
                word: w,
                prev: previousWord?.lowercased().trimmingCharacters(in: .punctuationCharacters),
                next: nextWord?.lowercased().trimmingCharacters(in: .punctuationCharacters),
                pauseBefore: pauseBefore,
                pauseAfter: pauseAfter,
                isStartOfSentence: isStartOfSentence
            )
        }

        return false
    }
}

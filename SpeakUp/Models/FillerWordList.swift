import Foundation

// MARK: - Filler Word Config

/// User-customizable filler word configuration.
nonisolated struct FillerWordConfig: Sendable {
    let customFillers: Set<String>        // user-added always-detected fillers
    let customContextFillers: Set<String> // user-added context-dependent fillers (pauseBefore && pauseAfter)
    let removedDefaults: Set<String>      // default fillers the user disabled

    nonisolated static let `default` = FillerWordConfig(customFillers: [], customContextFillers: [], removedDefaults: [])
}

// MARK: - Filler Words List

/// Pure word-list logic — consulted from nonisolated lexicon passes and
/// MainActor call sites alike.
nonisolated struct FillerWordList {
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

    static let contextDependentFillers: Set<String> = [
        "like", "so", "just", "well", "right", "okay",
        "actually", "basically", "literally", "honestly", "seriously"
    ]

    static let fillerPhrases: Set<String> = [
        "you know", "i mean", "sort of", "kind of"
    ]

    private static let verbPreceders: Set<String> = [
        "would", "do", "does", "did", "don't", "doesn't", "didn't",
        "i", "you", "we", "they", "he", "she", "it",
        "really", "actually", "also", "always", "never"
    ]

    private static let linkingVerbs: Set<String> = [
        "was", "is", "are", "were", "be", "been", "being",
        "felt", "looked", "seemed", "acted"
    ]

    private static let fillerFollowers: Set<String> = [
        "really", "totally", "super", "very", "so", "pretty",
        "kind", "sort", "completely", "absolutely", "honestly"
    ]

    static func isFillerWord(_ word: String) -> Bool {
        let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        if unconditionalFillers.contains(lowercased) {
            return true
        }

        let collapsed = collapseRepeatedChars(lowercased)
        if unconditionalFillers.contains(collapsed) {
            return true
        }

        return false
    }

    static func isFillerWord(
        _ word: String,
        previousWord: String?,
        nextWord: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool = false
    ) -> Bool {
        let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        if unconditionalFillers.contains(w) || unconditionalFillers.contains(collapseRepeatedChars(w)) {
            return true
        }

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
            return pauseBefore && pauseAfter
        }
    }

    private static func isLikeFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        if isStartOfSentence && pauseAfter {
            return true
        }

        if let p = prev, linkingVerbs.contains(p) {
            return true
        }

        if pauseBefore && pauseAfter {
            return true
        }

        if let n = next, fillerFollowers.contains(n) {
            return true
        }

        if let p = prev, verbPreceders.contains(p) {
            return false
        }

        if !pauseBefore && !pauseAfter {
            return false
        }

        return pauseBefore || pauseAfter
    }

    private static func isSoFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        if isStartOfSentence && pauseAfter {
            return true
        }

        if let p = prev, p == "not" {
            return false
        }

        if !pauseAfter && next != nil {
            return false
        }

        return pauseBefore && pauseAfter
    }

    private static func isJustFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {
        // "just" as filler is typically pause-surrounded and adds no meaning
        // "I, just, don't know" vs "I just arrived" (timing)

        if pauseBefore && pauseAfter {
            return true
        }

        return false
    }

    private static func isWellFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        if isStartOfSentence && pauseAfter {
            return true
        }

        if let p = prev, ["very", "quite", "as", "pretty", "really"].contains(p) {
            return false
        }

        if let n = next, ["done", "made", "known", "written", "said"].contains(n) {
            return false
        }

        return pauseBefore && pauseAfter
    }

    private static func isRightOkayFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {

        if let p = prev, ["the", "a", "an", "that", "this"].contains(p) {
            return false
        }

        return pauseBefore || pauseAfter
    }

    private static func isAdverbFiller(
        word: String,
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        if isStartOfSentence && pauseAfter {
            return true
        }

        if pauseBefore && pauseAfter {
            return true
        }

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

    static func isFillerWord(_ word: String, config: FillerWordConfig) -> Bool {
        let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let collapsed = collapseRepeatedChars(lowercased)

        // Removed by user — never match
        if config.removedDefaults.contains(lowercased) || config.removedDefaults.contains(collapsed) {
            return false
        }

        if config.customFillers.contains(lowercased) || config.customFillers.contains(collapsed) {
            return true
        }

        if unconditionalFillers.contains(lowercased) || unconditionalFillers.contains(collapsed) {
            return true
        }

        // Custom context fillers — false without context (same as default context-dependent behavior)
        return false
    }

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

        if config.customFillers.contains(w) || config.customFillers.contains(collapsed) {
            return true
        }

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

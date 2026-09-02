import Foundation

// MARK: - Value types

/// One span of a rendered context fragment: the crutch word itself or the
/// ordinary words around it.
nonisolated struct FragmentPiece: Hashable, Sendable {
    let text: String
    let isTarget: Bool
}

/// One ranked replacement proposal for a single occurrence of a crutch word.
/// Higher-ranked options came from more context-specific rules (numbers,
/// names, sentence position) rather than generic category advice.
nonisolated struct WordSwapOption: Hashable, Sendable {
    let replacement: String
    let cue: String?

    init(_ replacement: String, cue: String? = nil) {
        self.replacement = replacement
        self.cue = cue
    }
}

/// One concrete "here is where you said it, here is what to say instead"
/// moment backing a habit row.
nonisolated struct WordSwapOccurrence: Identifiable, Hashable, Sendable {
    let timestamp: TimeInterval
    let fragment: [FragmentPiece]
    let options: [WordSwapOption]

    var id: TimeInterval { timestamp }
    var best: WordSwapOption? { options.first }
}

// MARK: - Token

/// A single timed transcript word with everything disambiguation needs:
/// normalized text for matching, raw casing for fragments, timing for
/// pause-based sentence boundaries, and pipeline filler tagging.
nonisolated struct SwapToken: Hashable, Sendable {
    let text: String
    let raw: String
    let start: TimeInterval
    let end: TimeInterval
    let isPipelineFiller: Bool

    var endsSentence: Bool {
        raw.last.map { ".!?…".contains($0) } ?? false
    }
}

// MARK: - Suggester

/// Pure, deterministic, on-device swap suggestions. For one occurrence of a
/// crutch word inside its token stream, produce ONE primary replacement plus
/// up to two alternates — chosen from what actually surrounds the word
/// (numbers, proper nouns, sentence position), not from a flat list.
///
/// Rules are ordered most-specific-first per word; the first match wins, so
/// identical input always yields identical output.
nonisolated enum WordSwapSuggester {

    // MARK: Entry point

    /// Suggestions for one occurrence of `word` occupying `tokenRange`
    /// (multi-word hedges like "kind of" span several tokens).
    static func options(
        for word: String,
        category: CrutchCategory,
        tokenRange: Range<Int>,
        tokens: [SwapToken]
    ) -> [WordSwapOption] {
        let index = tokenRange.lowerBound
        switch word {
        case "like":
            return likeOptions(at: index, tokens)
        case "right", "okay", "alright", "yeah":
            return agreementMarkerOptions(at: index, tokens)
        case "so", "well":
            return openerOptions(at: index, tokens)
        case "just":
            return justOptions(at: index, tokens)
        case "really", "very", "super", "extremely", "truly", "totally",
             "completely", "absolutely", "seriously", "honestly":
            return intensifierOptions(word, at: index, tokens)
        case "literally":
            if isNumeric(token(index + 1, in: tokens)) {
                return [option("“exactly”", cue: "with numbers"),
                        option("cut it")]
            }
            return mappedSlice(word) ?? fallback(category)
        case "basically":
            if isSentenceStart(index, tokens),
               let next = token(index + 1, in: tokens),
               summaryOpeners.contains(next) {
                return [option("“In short”", cue: "summarizing, once per answer"),
                        option("cut it")]
            }
            return mappedSlice(word) ?? fallback(category)
        case "actually":
            let previous = token(index - 1, in: tokens)
            if isSentenceStart(index, tokens) || matches(previous, in: correctionCues) {
                return [option("“In fact”", cue: "when correcting or sharpening"),
                        option("cut it")]
            }
            return mappedSlice(word) ?? fallback(category)
        case "kind of", "sort of":
            return kindOfOptions(after: tokenRange.upperBound, tokens)
        case "things", "stuff":
            return vagueNounOptions(word, at: index, tokens)
        case "a lot":
            if token(tokenRange.upperBound, in: tokens) == "of" {
                return [option("quantify it — “70%”, “12 people”", cue: "“a lot of” hides the number"),
                        option("“considerably”, sparingly")]
            }
            return [option("“often”", cue: "frequency adverb beats vagueness"),
                    option("“frequently”"),
                    option("quantify instead")]
        default:
            if let own = LexiconInsightsEngine.alternatives[word], !own.isEmpty {
                return own.prefix(3).map { WordSwapOption($0) }
            }
            return fallback(category)
        }
    }

    // MARK: Per-word rules

    private static func likeOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(index + 1, in: tokens)
        let previous = token(index - 1, in: tokens)

        // "would like", "I like" — genuine verb, not a crutch.
        if matches(previous, in: verbalPreceders) {
            return hedgePause()
        }

        // "in like three weeks" — approximating a number.
        if isNumeric(next) {
            return [
                option("“about”", cue: "before numbers"),
                option("“roughly”"),
                option("pause silently")
            ]
        }

        // "it feels like we rushed" — hedged comparison after a perception verb.
        if matches(previous, in: perceptionVerbs), !isSentenceEnd(index, tokens) {
            return [
                option("“as if”", cue: "after feel / look / seem"),
                option("“as though”"),
                option("own the claim")
            ]
        }

        // Sentence-opening "Like, ..." — pure throat-clearing.
        if isSentenceStart(index, tokens) {
            return [
                option("cut it — start straight in", cue: "sentence opener"),
                option("a silent pause")
            ]
        }

        // "platforms like Figma" — introducing an example noun phrase.
        if startsNounPhrase(after: index, in: tokens) {
            return [
                option("“such as”", cue: "introducing an example"),
                option("“for example”"),
                option("pause silently")
            ]
        }

        return hedgePause()
    }

    private static func agreementMarkerOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        // Confirmation-seeking tag at the end of a thought: replace with a
        // real check-in used once, not every sentence.
        if isSentenceEnd(index, tokens) {
            return [
                option("hold silence — let it land", cue: "tag at sentence end"),
                option("“Does that make sense?”, at most once"),
                option("nod instead")
            ]
        }
        if isSentenceStart(index, tokens) {
            return [
                option("cut it — open on the point", cue: "throat-clearing opener"),
                option("a silent pause")
            ]
        }
        return hedgePause()
    }

    private static func openerOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        if isSentenceStart(index, tokens) {
            return [
                option("lead with the conclusion", cue: "sentence-opening filler"),
                option("one silent beat first")
            ]
        }
        return hedgePause()
    }

    private static func justOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(index + 1, in: tokens)

        // "I just want..." — the hedge shrinks your own ask; delete it.
        if let next, desireVerbs.contains(next) {
            return [
                option("“I \(next)”", cue: "drop “just” — state the ask"),
                option("drop “just” entirely"),
                option("“only”, when counting matters")
            ]
        }

        // "just three people" — counting sense has a real word.
        if isNumeric(next) {
            return [
                option("“only”", cue: "counting sense"),
                option("drop it")
            ]
        }

        return mappedSlice("just") ?? hedgeCut()
    }

    private static func intensifierOptions(_ word: String, at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(index + 1, in: tokens)

        // "really good" → "excellent": one strong word replaces two weak ones.
        if let next, let stronger = strengtheners[next] {
            return [
                option("“\(stronger)”", cue: "one strong word beats two"),
                option("quantify instead — give the number"),
                option("cut “\(word)”")
            ]
        }

        // Generic adjective underneath: at least name the move precisely.
        if let next, isAdjectiveish(next) {
            return [
                option("one stronger adjective", cue: "upgrade “\(word) \(next)”"),
                option("quantify instead"),
                option("cut “\(word)”")
            ]
        }

        return mappedSlice(word) ?? hedgeCut()
    }

    private static func kindOfOptions(after end: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(end, in: tokens)

        if isNumeric(next) {
            return [
                option("“about”", cue: "before numbers"),
                option("“roughly”"),
                option("drop it")
            ]
        }

        if let next, isAdjectiveish(next) || matches(next, in: verbCues) || isPastOrProgressiveVerb(next) {
            return [
                option("drop it — state it directly", cue: "hedged claim"),
                option("“somewhat”, sparingly"),
                option("be specific instead")
            ]
        }

        return mappedSlice("kind of") ?? hedgeCut()
    }

    private static func vagueNounOptions(_ word: String, at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        // "things like planning" — the example is already in reach; name it.
        if token(index + 1, in: tokens) == "like",
           let referent = token(index + 2, in: tokens),
           referent.count <= 12 {
            return [
                option("name them — “including \(referent)”", cue: "the example is already in reach"),
                option("count them — “three things”, then name them"),
                option("the specifics")
            ]
        }

        return mappedSlice(word) ?? fallback(.vague)
    }

    // MARK: Shared option sets

    private static func hedgePause() -> [WordSwapOption] {
        [
            option("a silent pause", cue: "mid-sentence hedge"),
            option("cut it entirely"),
            option("“I mean”, when reframing")
        ]
    }

    private static func hedgeCut() -> [WordSwapOption] {
        [
            option("cut it", cue: "the claim stands alone"),
            option("one stronger word"),
            option("quantify instead")
        ]
    }

    private static func fallback(_ category: CrutchCategory) -> [WordSwapOption] {
        switch category {
        case .filler:
            return [option("a silent pause", cue: "replace the hesitation sound"),
                    option("breathe through it")]
        case .hedge:
            return [option("state it directly", cue: "drop the hedge, own the claim"),
                    option("own the claim")]
        case .intensifier:
            return hedgeCut()
        case .vague:
            return [option("name the specifics", cue: "say the exact thing")]
        case .structural:
            return [option("vary the opening", cue: "same frame three times reads as a tic"),
                    option("name the list once, then the items"),
                    option("lead with the conclusion")]
        }
    }

    /// First entries of the static alternatives map as plain options.
    private static func mappedSlice(_ word: String) -> [WordSwapOption]? {
        guard let own = LexiconInsightsEngine.alternatives[word], !own.isEmpty else { return nil }
        return own.prefix(3).map { WordSwapOption($0) }
    }

    private static func option(_ replacement: String, cue: String? = nil) -> WordSwapOption {
        WordSwapOption(replacement, cue: cue)
    }

    // MARK: Row-level ranking

    /// The dominant replacements across a habit's occurrences: most frequent
    /// pattern first, ties broken by earliest use, then alphabetically. This
    /// turns per-occurrence picks into one row-level suggestion.
    static func dominantReplacements(in occurrences: [WordSwapOccurrence]) -> [String] {
        var frequency: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order: [String] = []

        for (offset, occurrence) in occurrences.enumerated() {
            guard let best = occurrence.best else { continue }
            if firstSeen[best.replacement] == nil {
                firstSeen[best.replacement] = offset
                order.append(best.replacement)
            }
            frequency[best.replacement, default: 0] += 1
        }

        let ranked = order.sorted { lhs, rhs in
            if frequency[lhs] != frequency[rhs] { return frequency[lhs]! > frequency[rhs]! }
            if firstSeen[lhs] != firstSeen[rhs] { return firstSeen[lhs]! < firstSeen[rhs]! }
            return lhs < rhs
        }

        return Array(ranked.prefix(3))
    }

    /// The winning option itself, so its cue can render beside the chips.
    static func primaryOption(in occurrences: [WordSwapOccurrence]) -> WordSwapOption? {
        guard let winner = dominantReplacements(in: occurrences).first,
              let match = occurrences.first(where: { $0.best?.replacement == winner })
        else { return nil }
        return match.best
    }

    // MARK: Fragment building

    /// ±`radius` words around the occurrence range, original casing
    /// preserved, every token of a multi-word hit marked. Ellipses mark
    /// truncation on either side.
    static func fragment(
        tokenRange: Range<Int>,
        radius: Int = 6,
        in tokens: [SwapToken]
    ) -> [FragmentPiece] {
        guard tokens.indices.contains(tokenRange.lowerBound) else { return [] }

        let lower = max(0, tokenRange.lowerBound - radius)
        let upper = min(tokens.count - 1, max(tokenRange.upperBound - 1, tokenRange.lowerBound) + radius)

        var pieces: [FragmentPiece] = []
        if lower > 0 {
            pieces.append(FragmentPiece(text: "…", isTarget: false))
        }
        for position in lower...upper {
            pieces.append(FragmentPiece(text: tokens[position].raw, isTarget: tokenRange.contains(position)))
        }
        if upper < tokens.count - 1 {
            pieces.append(FragmentPiece(text: "…", isTarget: false))
        }
        return pieces
    }

    // MARK: Context predicates

    private static func token(_ index: Int, in tokens: [SwapToken]) -> String? {
        guard tokens.indices.contains(index) else { return nil }
        return tokens[index].text
    }

    private static func isSentenceStart(_ index: Int, _ tokens: [SwapToken]) -> Bool {
        guard index > 0 else { return true }
        let previous = tokens[index - 1]
        return previous.endsSentence || tokens[index].start - previous.end > 0.9
    }

    private static func isSentenceEnd(_ index: Int, _ tokens: [SwapToken]) -> Bool {
        guard index < tokens.count - 1 else { return true }
        return tokens[index].endsSentence || tokens[index + 1].start - tokens[index].end > 0.9
    }

    private static func isNumeric(_ word: String?) -> Bool {
        guard let word else { return false }
        return word.rangeOfCharacter(from: .decimalDigits) != nil || numberWords.contains(word)
    }

    private static func isAdjectiveish(_ word: String) -> Bool {
        commonAdjectives.contains(word)
            || adjectiveSuffixes.contains { word.hasSuffix($0) && word.count >= 5 }
    }

    private static func isPastOrProgressiveVerb(_ word: String) -> Bool {
        word.count > 3 && (word.hasSuffix("ed") || word.hasSuffix("ing"))
    }

    private static func matches(_ word: String?, in set: Set<String>) -> Bool {
        guard let word else { return false }
        return set.contains(word)
    }

    private static func startsNounPhrase(after index: Int, in tokens: [SwapToken]) -> Bool {
        guard let next = token(index + 1, in: tokens) else { return false }
        if determiners.contains(next) { return true }
        if isNumeric(next) { return true }
        if isProperNounAt(index + 1, in: tokens) { return true }
        // Plural-ish follower ("platforms like Slack") without a determiner.
        return next.count > 3 && next.hasSuffix("s") && !next.hasSuffix("ss") && !verbLikeSEndings.contains(next)
    }

    private static func isProperNounAt(_ index: Int, in tokens: [SwapToken]) -> Bool {
        guard tokens.indices.contains(index), tokens[index].raw.count > 1 else { return false }
        guard let first = tokens[index].raw.first else { return false }
        return first.isUppercase && !isSentenceStart(index, tokens)
    }

    // MARK: Vocabulary cues

    private static let numberWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "twenty", "thirty", "forty", "fifty", "sixty",
        "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion", "percent"
    ]

    private static let strengtheners: [String: String] = [
        "good": "excellent",
        "great": "outstanding",
        "nice": "impressive",
        "strong": "decisive",
        "big": "substantial",
        "important": "critical",
        "interesting": "compelling",
        "hard": "demanding",
        "fast": "rapid",
        "bad": "poor",
        "clear": "unambiguous",
        "simple": "straightforward",
        "useful": "valuable",
        "effective": "high-impact",
        "common": "widespread",
        "excited": "thrilled",
        "proud": "honored",
        "confident": "certain"
    ]

    private static let commonAdjectives: Set<String> = [
        "good", "great", "bad", "big", "small", "hard", "easy", "fast", "slow",
        "new", "old", "long", "short", "high", "low", "early", "late", "strong",
        "weak", "clear", "simple", "difficult", "interesting", "different",
        "similar", "happy", "proud", "excited", "tough"
    ]

    private static let adjectiveSuffixes: Set<String> = [
        "ful", "ous", "ive", "able", "ible", "ical", "less", "ant", "ent", "ish"
    ]

    private static let perceptionVerbs: Set<String> = [
        "feel", "feels", "felt", "look", "looks", "looked",
        "seem", "seems", "seemed", "sound", "sounds", "sounded"
    ]

    private static let verbalPreceders: Set<String> = [
        "do", "does", "did", "don't", "doesn't", "didn't",
        "would", "will", "won't", "can", "could",
        "i", "you", "we", "they", "he", "she"
    ]

    private static let desireVerbs: Set<String> = [
        "want", "wanted", "need", "needed", "think", "thought", "know",
        "say", "said", "ask", "asked", "tell", "told", "check", "checking",
        "make", "making", "give", "giving"
    ]

    private static let determiners: Set<String> = [
        "the", "a", "an", "my", "our", "your", "his", "her", "its", "their",
        "this", "that", "these", "those", "some", "both", "each", "every"
    ]

    private static let summaryOpeners: Set<String> = [
        "we", "the", "this", "it", "what", "here"
    ]

    private static let verbCues: Set<String> = [
        "want", "wanted", "need", "think", "feel", "felt", "know", "said",
        "going", "trying", "wondering", "struggling"
    ]

    private static let correctionCues: Set<String> = [
        "no", "well", "but"
    ]

    private static let verbLikeSEndings: Set<String> = [
        "does", "goes", "says", "was", "has", "gets", "puts", "runs", "makes",
        "takes", "gives", "needs", "wants", "means", "seems", "feels", "looks",
        "works", "helps", "keeps", "lets", "sets", "hits", "fits", "wins",
        "cuts", "acts", "asks", "ends", "adds", "owns", "leads", "builds",
        "ships", "sells", "tells", "shows", "knows", "thinks", "finds",
        "holds", "stands", "sends", "spends", "meets", "starts", "stops",
        "its", "this", "yes", "less", "plus"
    ]
}

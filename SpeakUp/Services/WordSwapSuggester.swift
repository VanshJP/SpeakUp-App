import Foundation

// MARK: - Value types

/// One span of a rendered context fragment: the crutch word itself or the
/// ordinary words around it.
nonisolated struct FragmentPiece: Hashable, Sendable {
    let text: String
    let isTarget: Bool
}

/// What a swap does to the sentence *mechanically*, so the card can render the
/// corrected line instead of only naming the fix.
///
/// `.advice` is the honest escape hatch: "quantify instead" has no single
/// substitution, so no rewrite is offered rather than a wrong one. `.pause`
/// rewrites identically to `.delete` but stays distinct — "replace it with
/// silence" and "just cut it" are the same edit and different coaching.
nonisolated struct SwapEdit: Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case delete
        case pause
        case replace
        case advice
    }

    let kind: Kind
    /// Replacement text for `.replace`; empty otherwise.
    let text: String
    /// Tokens consumed *after* the crutch span — "really good" → "excellent"
    /// eats the adjective too, so the rewrite is not "excellent good".
    let extraTokens: Int

    static let delete = SwapEdit(kind: .delete, text: "", extraTokens: 0)
    static let pause = SwapEdit(kind: .pause, text: "", extraTokens: 0)
    static let advice = SwapEdit(kind: .advice, text: "", extraTokens: 0)

    static func replace(_ text: String, extraTokens: Int = 0) -> SwapEdit {
        SwapEdit(kind: .replace, text: text, extraTokens: extraTokens)
    }

    static func drop(extraTokens: Int) -> SwapEdit {
        SwapEdit(kind: .delete, text: "", extraTokens: extraTokens)
    }

    /// Produces a concrete rewritten line rather than only naming a fix.
    var isMechanical: Bool { kind != .advice }

    /// Two options that do the same thing to the sentence collapse to one, so
    /// a row never prints "cut it" beside "drop it entirely".
    var dedupeKey: String {
        switch kind {
        case .delete: return "delete\(extraTokens)"
        case .pause: return "pause"
        case .replace: return "replace:\(text.lowercased())/\(extraTokens)"
        case .advice: return "advice"
        }
    }

    /// Best-effort reading of a legacy alternatives-map string. Conservative by
    /// design: only a string that is *entirely* one quoted phrase becomes a
    /// substitution, because `“only” when counting matters` is a condition, not
    /// an instruction to swap in "only".
    static func inferred(from replacement: String) -> SwapEdit {
        let trimmed = replacement.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()

        if pausePhrases.contains(lowered) { return .pause }
        if deletePhrases.contains(lowered) { return .delete }
        if lowered.hasPrefix("cut ") && lowered.hasSuffix(" entirely") { return .delete }
        if lowered.hasPrefix("drop ") && lowered.hasSuffix(" entirely") { return .delete }

        if trimmed.hasPrefix("\u{201C}"), trimmed.hasSuffix("\u{201D}") {
            let inner = String(trimmed.dropFirst().dropLast())
            if !inner.isEmpty, !inner.contains("\u{201C}") {
                return .replace(inner)
            }
        }

        return .advice
    }

    private static let deletePhrases: Set<String> = [
        "cut it", "cut it entirely", "cut entirely", "drop it", "drop it entirely",
        "cut this", "state it directly", "own the claim", "end cleanly",
        "end the sentence there", "commit to a position"
    ]

    private static let pausePhrases: Set<String> = [
        "a pause", "a silent pause", "pause silently", "one silent beat first",
        "pause and check eyes instead"
    ]
}

/// One ranked replacement proposal for a single occurrence of a crutch word.
/// Higher-ranked options came from more context-specific rules (numbers,
/// names, sentence position) rather than generic category advice.
nonisolated struct WordSwapOption: Hashable, Sendable {
    let replacement: String
    let cue: String?
    let edit: SwapEdit

    init(_ replacement: String, cue: String? = nil, edit: SwapEdit? = nil) {
        self.replacement = replacement
        self.cue = cue
        self.edit = edit ?? SwapEdit.inferred(from: replacement)
    }
}

/// One concrete "here is where you said it, here is what to say instead"
/// moment backing a habit row.
nonisolated struct WordSwapOccurrence: Identifiable, Hashable, Sendable {
    let timestamp: TimeInterval
    let fragment: [FragmentPiece]
    /// The same sentence with the winning swap applied — nil when the advice
    /// has no single mechanical edit ("quantify instead").
    let rewritten: [FragmentPiece]?
    let options: [WordSwapOption]

    var id: TimeInterval { timestamp }
    var best: WordSwapOption? { options.first }

    /// Whisper's alignment heads emit zero starts often enough that a tap on
    /// such a moment jumps to the top of the take. Matches the transcript's
    /// own rule (recording-detail invariant 18).
    var isPlayable: Bool { timestamp > 0 && timestamp.isFinite }

    init(
        timestamp: TimeInterval,
        fragment: [FragmentPiece],
        rewritten: [FragmentPiece]? = nil,
        options: [WordSwapOption]
    ) {
        self.timestamp = timestamp
        self.fragment = fragment
        self.rewritten = rewritten
        self.options = options
    }
}

/// Occurrences that earned the *same* advice, collapsed into one teachable
/// moment. Three "just"s in one sentence pattern are one lesson with three
/// play points; three "just"s in three different patterns are three lessons.
nonisolated struct WordSwapMoment: Identifiable, Hashable, Sendable {
    let option: WordSwapOption
    let occurrences: [WordSwapOccurrence]

    /// Distinct per habit: two moments differ by the advice that groups them,
    /// and equal timestamps must never collapse two rows in a `ForEach`.
    var id: String { "\(option.replacement)@\(occurrences.first?.timestamp ?? -1)" }
    var example: WordSwapOccurrence? { occurrences.first }
    var count: Int { occurrences.count }
    var playable: [WordSwapOccurrence] { occurrences.filter(\.isPlayable) }

    /// The corrected sentence as plain text, ready to hand to Read Aloud so
    /// the user can rehearse it instead of only reading it.
    ///
    /// Nil when there is no rewrite, or when the line is too short to be worth
    /// scoring — "I want" is a fragment, not a rep. Ellipses are dropped:
    /// they mark where the quote was cut, and nobody says them out loud.
    var practiceLine: String? {
        guard let pieces = example?.rewritten else { return nil }

        let text = pieces
            .filter { $0.text != "\u{2026}" }
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count >= 12,
              text.split(separator: " ").count >= 4
        else { return nil }

        return text
    }
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
        raw.last.map { ".!?\u{2026}".contains($0) } ?? false
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

    /// Everything one occurrence needs to render: ranked options, the sentence
    /// it happened in, and that sentence with the winning swap applied.
    static func occurrence(
        for word: String,
        category: CrutchCategory,
        tokenRange: Range<Int>,
        radius: Int = 6,
        tokens: [SwapToken]
    ) -> WordSwapOccurrence {
        let options = self.options(for: word, category: category, tokenRange: tokenRange, tokens: tokens)
        return WordSwapOccurrence(
            timestamp: tokens.indices.contains(tokenRange.lowerBound) ? tokens[tokenRange.lowerBound].start : 0,
            fragment: fragment(tokenRange: tokenRange, radius: radius, in: tokens),
            rewritten: options.first.flatMap {
                rewrite(tokenRange: tokenRange, edit: $0.edit, radius: radius, in: tokens)
            },
            options: options
        )
    }

    /// Suggestions for one occurrence of `word` occupying `tokenRange`
    /// (multi-word hedges like "kind of" span several tokens).
    static func options(
        for word: String,
        category: CrutchCategory,
        tokenRange: Range<Int>,
        tokens: [SwapToken]
    ) -> [WordSwapOption] {
        deduplicated(rawOptions(for: word, category: category, tokenRange: tokenRange, tokens: tokens))
    }

    private static func rawOptions(
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
        case "maybe", "probably", "perhaps":
            return epistemicHedgeOptions(word, at: index, tokens)
        case "you know":
            return youKnowOptions(range: tokenRange, tokens)
        case "i mean":
            return iMeanOptions(at: index, tokens)
        case "i think", "i guess", "i suppose", "i believe", "i feel like":
            return selfHedgeOptions(word, at: index, tokens)
        case "literally":
            if isNumeric(token(index + 1, in: tokens)) {
                return [option("\u{201C}exactly\u{201D}", cue: "with numbers", edit: .replace("exactly")),
                        option("cut it", edit: .delete)]
            }
            return mappedSlice(word) ?? fallback(category)
        case "basically":
            if isSentenceStart(index, tokens),
               let next = token(index + 1, in: tokens),
               summaryOpeners.contains(next) {
                return [option("\u{201C}In short\u{201D}", cue: "summarizing, once per answer", edit: .replace("In short")),
                        option("cut it", edit: .delete)]
            }
            return mappedSlice(word) ?? fallback(category)
        case "actually":
            let previous = token(index - 1, in: tokens)
            if isSentenceStart(index, tokens) || matches(previous, in: correctionCues) {
                return [option("\u{201C}In fact\u{201D}", cue: "when correcting or sharpening", edit: .replace("In fact")),
                        option("cut it", edit: .delete)]
            }
            return mappedSlice(word) ?? fallback(category)
        case "kind of", "sort of":
            return kindOfOptions(after: tokenRange.upperBound, tokens)
        case "things", "stuff":
            return vagueNounOptions(word, at: index, tokens)
        case "something", "somehow", "whatever":
            return vagueReferentOptions(word, at: index, tokens)
        case "a lot":
            if token(tokenRange.upperBound, in: tokens) == "of" {
                return [option("quantify it: \u{201C}70%\u{201D}, \u{201C}12 people\u{201D}", cue: "\u{201C}a lot of\u{201D} hides the number", edit: .advice),
                        option("\u{201C}considerably\u{201D}, sparingly", edit: .advice)]
            }
            return [option("\u{201C}often\u{201D}", cue: "frequency adverb beats vagueness", edit: .replace("often")),
                    option("\u{201C}frequently\u{201D}", edit: .replace("frequently")),
                    option("quantify instead", edit: .advice)]
        default:
            if let own = LexiconInsightsEngine.alternatives[word], !own.isEmpty {
                return own.prefix(3).map { WordSwapOption($0) }
            }
            return fallback(category)
        }
    }

    /// Two options that edit the sentence identically are one option wearing
    /// two hats. Keeps the first — rules are ordered most-specific-first, so
    /// the survivor is always the better-explained one.
    static func deduplicated(_ options: [WordSwapOption]) -> [WordSwapOption] {
        var seenEdits: Set<String> = []
        var seenText: Set<String> = []
        var result: [WordSwapOption] = []

        for option in options {
            let text = option.replacement.lowercased()
            guard !seenText.contains(text) else { continue }
            if option.edit.kind != .advice {
                guard !seenEdits.contains(option.edit.dedupeKey) else { continue }
                seenEdits.insert(option.edit.dedupeKey)
            }
            seenText.insert(text)
            result.append(option)
        }
        return result
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
                option("\u{201C}about\u{201D}", cue: "before numbers", edit: .replace("about")),
                option("\u{201C}roughly\u{201D}", edit: .replace("roughly")),
                option("pause silently", edit: .pause)
            ]
        }

        // "it feels like we rushed" — hedged comparison after a perception verb.
        if matches(previous, in: perceptionVerbs), !isSentenceEnd(index, tokens) {
            return [
                option("\u{201C}as if\u{201D}", cue: "after feel / look / seem", edit: .replace("as if")),
                option("\u{201C}as though\u{201D}", edit: .replace("as though")),
                option("own the claim", edit: .advice)
            ]
        }

        // Sentence-opening "Like, ..." — pure throat-clearing.
        if isSentenceStart(index, tokens) {
            return [
                option("cut it. Start straight in", cue: "sentence opener", edit: .delete),
                option("a silent pause", edit: .pause)
            ]
        }

        // "platforms like Figma" — introducing an example noun phrase.
        if startsNounPhrase(after: index, in: tokens) {
            return [
                option("\u{201C}such as\u{201D}", cue: "introducing an example", edit: .replace("such as")),
                option("\u{201C}for example\u{201D}", edit: .replace("for example")),
                option("pause silently", edit: .pause)
            ]
        }

        return hedgePause()
    }

    private static func agreementMarkerOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        // Confirmation-seeking tag at the end of a thought: replace with a
        // real check-in used once, not every sentence.
        if isSentenceEnd(index, tokens) {
            return [
                option("hold silence. Let it land", cue: "tag at sentence end", edit: .delete),
                option("\u{201C}Does that make sense?\u{201D}, at most once", edit: .advice),
                option("nod instead", edit: .advice)
            ]
        }
        if isSentenceStart(index, tokens) {
            return [
                option("cut it. Open on the point", cue: "throat-clearing opener", edit: .delete),
                option("a silent pause", edit: .pause)
            ]
        }
        return hedgePause()
    }

    private static func openerOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        if isSentenceStart(index, tokens) {
            return [
                option("lead with the conclusion", cue: "sentence-opening filler", edit: .delete),
                option("one silent beat first", edit: .pause)
            ]
        }
        return hedgePause()
    }

    private static func justOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(index + 1, in: tokens)

        // "I just want..." — the hedge shrinks your own ask; delete it.
        if let next, desireVerbs.contains(next) {
            return [
                option("\u{201C}I \(next)\u{201D}", cue: "drop \u{201C}just\u{201D} and state the ask", edit: .delete),
                option("\u{201C}only\u{201D}, when counting matters", edit: .advice)
            ]
        }

        // "just three people" — counting sense has a real word.
        if isNumeric(next) {
            return [
                option("\u{201C}only\u{201D}", cue: "counting sense", edit: .replace("only")),
                option("drop it", edit: .delete)
            ]
        }

        return mappedSlice("just") ?? hedgeCut()
    }

    private static func intensifierOptions(_ word: String, at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(index + 1, in: tokens)

        // "really good" → "excellent": one strong word replaces two weak ones.
        if let next, let stronger = strengtheners[next] {
            return [
                option("\u{201C}\(stronger)\u{201D}", cue: "one strong word beats two", edit: .replace(stronger, extraTokens: 1)),
                option("quantify instead. Give the number", edit: .advice),
                option("cut \u{201C}\(word)\u{201D}", edit: .delete)
            ]
        }

        // Generic adjective underneath: at least name the move precisely.
        if let next, isAdjectiveish(next) {
            return [
                option("one stronger adjective", cue: "upgrade \u{201C}\(word) \(next)\u{201D}", edit: .advice),
                option("quantify instead", edit: .advice),
                option("cut \u{201C}\(word)\u{201D}", edit: .delete)
            ]
        }

        return mappedSlice(word) ?? hedgeCut()
    }

    /// "maybe / probably / perhaps" read as low confidence in an answer the
    /// speaker already has. Commit, or price the uncertainty honestly.
    private static func epistemicHedgeOptions(_ word: String, at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        if isNumeric(token(index + 1, in: tokens)) {
            return [
                option("\u{201C}about\u{201D}", cue: "before a number, say the range", edit: .replace("about")),
                option("give the range: \u{201C}three to five\u{201D}", edit: .advice),
                option("cut \u{201C}\(word)\u{201D}", edit: .delete)
            ]
        }
        return [
            option("commit to the answer", cue: "you already know this one", edit: .delete),
            option("\u{201C}likely\u{201D}", edit: .replace("likely")),
            option("price it: \u{201C}9 times in 10\u{201D}", edit: .advice)
        ]
    }

    /// "you know" asks the listener to fill the gap. At a sentence end it is a
    /// approval-seeking tag; mid-sentence it is pure filler.
    private static func youKnowOptions(range: Range<Int>, _ tokens: [SwapToken]) -> [WordSwapOption] {
        if isSentenceEnd(range.upperBound - 1, tokens) {
            return [
                option("hold the silence", cue: "tag asking for agreement", edit: .delete),
                option("\u{201C}Does that track?\u{201D}, at most once", edit: .advice)
            ]
        }
        return [
            option("cut it", cue: "the listener does not know — tell them", edit: .delete),
            option("a silent pause", edit: .pause)
        ]
    }

    /// "I mean" is a repair marker. Opening with it says the last sentence
    /// failed; mid-sentence it is a legitimate restatement worth naming.
    private static func iMeanOptions(at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        if isSentenceStart(index, tokens) {
            return [
                option("cut it. Say it once, clearly", cue: "opening repair marker", edit: .delete),
                option("a silent pause", edit: .pause)
            ]
        }
        return [
            option("\u{201C}that is\u{201D}", cue: "genuine restatement", edit: .replace("that is")),
            option("\u{201C}put differently\u{201D}", edit: .replace("put differently")),
            option("cut it", edit: .delete)
        ]
    }

    /// "I think / I guess" in front of a claim halves it. Opening a sentence
    /// with one is the costly case — that is the position of authority.
    private static func selfHedgeOptions(_ word: String, at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        if isSentenceStart(index, tokens) {
            return [
                option("state it directly", cue: "the claim is stronger unhedged", edit: .delete),
                option("\u{201C}My read is\u{201D}", edit: .replace("My read is")),
                option("\u{201C}I'd argue\u{201D}", edit: .replace("I'd argue"))
            ]
        }
        return mappedSlice(word) ?? fallback(.hedge)
    }

    private static func kindOfOptions(after end: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(end, in: tokens)

        if isNumeric(next) {
            return [
                option("\u{201C}about\u{201D}", cue: "before numbers", edit: .replace("about")),
                option("\u{201C}roughly\u{201D}", edit: .replace("roughly")),
                option("drop it", edit: .delete)
            ]
        }

        if let next, isAdjectiveish(next) || matches(next, in: verbCues) || isPastOrProgressiveVerb(next) {
            return [
                option("drop it. State it directly", cue: "hedged claim", edit: .delete),
                option("\u{201C}somewhat\u{201D}, sparingly", edit: .advice),
                option("be specific instead", edit: .advice)
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
                option("name them: \u{201C}including \(referent)\u{201D}", cue: "the example is already in reach", edit: .advice),
                option("count them: \u{201C}three things\u{201D}, then name them", edit: .advice),
                option("the specifics", edit: .advice)
            ]
        }

        return mappedSlice(word) ?? fallback(.vague)
    }

    /// "something that I enjoy" is a noun-shaped hole: the sentence commits to
    /// a thing and then declines to name it.
    private static func vagueReferentOptions(_ word: String, at index: Int, _ tokens: [SwapToken]) -> [WordSwapOption] {
        let next = token(index + 1, in: tokens)

        if word == "something", next == "that" || next == "like" {
            return [
                option("name the thing itself", cue: "\u{201C}something \(next ?? "that")\u{2026}\u{201D} is a noun-shaped hole", edit: .advice),
                option("the exact thing you did", edit: .advice)
            ]
        }

        if word == "somehow" {
            return [
                option("the actual mechanism", cue: "\u{201C}somehow\u{201D} skips the how", edit: .advice),
                option("cut it", edit: .delete)
            ]
        }

        return mappedSlice(word) ?? fallback(.vague)
    }

    // MARK: Shared option sets

    private static func hedgePause() -> [WordSwapOption] {
        [
            option("a silent pause", cue: "mid-sentence hedge", edit: .pause),
            option("cut it entirely", edit: .delete),
            option("\u{201C}I mean\u{201D}, when reframing", edit: .advice)
        ]
    }

    private static func hedgeCut() -> [WordSwapOption] {
        [
            option("cut it", cue: "the claim stands alone", edit: .delete),
            option("one stronger word", edit: .advice),
            option("quantify instead", edit: .advice)
        ]
    }

    private static func fallback(_ category: CrutchCategory) -> [WordSwapOption] {
        switch category {
        case .filler:
            return [option("a silent pause", cue: "replace the hesitation sound", edit: .pause),
                    option("breathe through it", edit: .advice)]
        case .hedge:
            return [option("state it directly", cue: "drop the hedge, own the claim", edit: .delete),
                    option("own the claim", edit: .advice)]
        case .intensifier:
            return hedgeCut()
        case .vague:
            return [option("name the specifics", cue: "say the exact thing", edit: .advice)]
        case .structural:
            return [option("vary the opening", cue: "same frame three times reads as a tic", edit: .advice),
                    option("name the list once, then the items", edit: .advice),
                    option("lead with the conclusion", edit: .advice)]
        }
    }

    /// First entries of the static alternatives map as plain options. Edits are
    /// inferred from the copy, so map-sourced rows still rewrite and still
    /// collapse duplicate deletions.
    private static func mappedSlice(_ word: String) -> [WordSwapOption]? {
        guard let own = LexiconInsightsEngine.alternatives[word], !own.isEmpty else { return nil }
        return own.prefix(3).map { WordSwapOption($0) }
    }

    private static func option(_ replacement: String, cue: String? = nil, edit: SwapEdit? = nil) -> WordSwapOption {
        WordSwapOption(replacement, cue: cue, edit: edit)
    }

    // MARK: Row-level ranking

    /// The dominant options across a habit's occurrences: most frequent
    /// pattern first, ties broken by earliest use, then alphabetically. This
    /// turns per-occurrence picks into one row-level suggestion.
    static func dominantOptions(in occurrences: [WordSwapOccurrence]) -> [WordSwapOption] {
        var frequency: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var byReplacement: [String: WordSwapOption] = [:]
        var order: [String] = []

        for (offset, occurrence) in occurrences.enumerated() {
            guard let best = occurrence.best else { continue }
            if firstSeen[best.replacement] == nil {
                firstSeen[best.replacement] = offset
                byReplacement[best.replacement] = best
                order.append(best.replacement)
            }
            frequency[best.replacement, default: 0] += 1
        }

        let ranked = order.sorted { lhs, rhs in
            if frequency[lhs] != frequency[rhs] { return frequency[lhs]! > frequency[rhs]! }
            if firstSeen[lhs] != firstSeen[rhs] { return firstSeen[lhs]! < firstSeen[rhs]! }
            return lhs < rhs
        }

        return ranked.prefix(3).compactMap { byReplacement[$0] }
    }

    /// The winning option itself, so its cue can render beside the chips.
    static func primaryOption(in occurrences: [WordSwapOccurrence]) -> WordSwapOption? {
        dominantOptions(in: occurrences).first
    }

    /// Distinct lessons inside one habit, strongest first. Occurrences sharing
    /// advice group together so the card shows three play points under one
    /// fix, not the same fix printed three times.
    static func moments(in occurrences: [WordSwapOccurrence], limit: Int = 3) -> [WordSwapMoment] {
        var grouped: [String: [WordSwapOccurrence]] = [:]
        var options: [String: WordSwapOption] = [:]
        var firstSeen: [String: Int] = [:]
        var order: [String] = []

        for (offset, occurrence) in occurrences.enumerated() {
            guard let best = occurrence.best else { continue }
            let key = best.replacement
            if firstSeen[key] == nil {
                firstSeen[key] = offset
                options[key] = best
                order.append(key)
            }
            grouped[key, default: []].append(occurrence)
        }

        let ranked = order.sorted { lhs, rhs in
            let left = grouped[lhs]?.count ?? 0
            let right = grouped[rhs]?.count ?? 0
            if left != right { return left > right }
            if firstSeen[lhs] != firstSeen[rhs] { return firstSeen[lhs]! < firstSeen[rhs]! }
            return lhs < rhs
        }

        return ranked.prefix(limit).compactMap { key in
            guard let option = options[key], let group = grouped[key] else { return nil }
            return WordSwapMoment(option: option, occurrences: group)
        }
    }

    // MARK: Fragment building

    /// The token window a fragment renders, clamped to sentence boundaries
    /// when one falls inside `radius`. A quote that starts where the sentence
    /// starts reads as speech; one that starts mid-clause reads as a glitch.
    private static func window(
        around tokenRange: Range<Int>,
        radius: Int,
        in tokens: [SwapToken]
    ) -> (lower: Int, upper: Int, truncatedLeft: Bool, truncatedRight: Bool)? {
        guard tokens.indices.contains(tokenRange.lowerBound) else { return nil }

        var lower = max(0, tokenRange.lowerBound - radius)
        var truncatedLeft = lower > 0

        var scan = tokenRange.lowerBound
        while scan > lower, !isSentenceStart(scan, tokens) {
            scan -= 1
        }
        if scan > lower || isSentenceStart(scan, tokens) {
            lower = scan
            truncatedLeft = lower > 0 && !isSentenceStart(lower, tokens)
        }

        let spanEnd = min(tokens.count - 1, max(tokenRange.upperBound - 1, tokenRange.lowerBound))
        var upper = min(tokens.count - 1, spanEnd + radius)
        var truncatedRight = upper < tokens.count - 1

        var forward = spanEnd
        while forward < upper, !isSentenceEnd(forward, tokens) {
            forward += 1
        }
        if forward < upper {
            upper = forward
            truncatedRight = false
        } else if isSentenceEnd(upper, tokens) {
            truncatedRight = false
        }

        return (lower, upper, truncatedLeft, truncatedRight)
    }

    /// Up to `radius` words around the occurrence range, original casing
    /// preserved, every token of a multi-word hit marked. Ellipses mark
    /// truncation on either side.
    static func fragment(
        tokenRange: Range<Int>,
        radius: Int = 6,
        in tokens: [SwapToken]
    ) -> [FragmentPiece] {
        guard let bounds = window(around: tokenRange, radius: radius, in: tokens) else { return [] }

        var pieces: [FragmentPiece] = []
        if bounds.truncatedLeft {
            pieces.append(FragmentPiece(text: "\u{2026}", isTarget: false))
        }
        for position in bounds.lower...bounds.upper {
            pieces.append(FragmentPiece(text: tokens[position].raw, isTarget: tokenRange.contains(position)))
        }
        if bounds.truncatedRight {
            pieces.append(FragmentPiece(text: "\u{2026}", isTarget: false))
        }
        return pieces
    }

    /// The same window with `edit` applied: the crutch removed or replaced,
    /// capitalization repaired, and the punctuation it was carrying handed
    /// back to the word before it. `isTarget` marks the *new* words so the
    /// card can tint the fix. Nil when the advice is not a single edit.
    static func rewrite(
        tokenRange: Range<Int>,
        edit: SwapEdit,
        radius: Int = 6,
        in tokens: [SwapToken]
    ) -> [FragmentPiece]? {
        guard edit.isMechanical,
              let bounds = window(around: tokenRange, radius: radius, in: tokens)
        else { return nil }

        let removalEnd = min(tokens.count, tokenRange.upperBound + max(0, edit.extraTokens))
        let removal = tokenRange.lowerBound..<removalEnd
        guard removal.lowerBound < removal.upperBound else { return nil }

        let upper = max(bounds.upper, removal.upperBound - 1)
        guard upper < tokens.count else { return nil }

        let startedSentence = isSentenceStart(tokenRange.lowerBound, tokens)
        let carried = trailingPunctuation(of: tokens[removal.upperBound - 1].raw)

        var body: [FragmentPiece] = []
        var insertedReplacement = false

        for position in bounds.lower...upper {
            if removal.contains(position) {
                if edit.kind == .replace, !insertedReplacement {
                    let text = startedSentence ? capitalizedFirst(edit.text) : edit.text
                    body.append(FragmentPiece(text: text, isTarget: true))
                    insertedReplacement = true
                }
                continue
            }
            body.append(FragmentPiece(text: tokens[position].raw, isTarget: false))
        }

        guard !body.isEmpty else { return nil }

        // A deleted word took its comma or full stop with it — give the
        // punctuation back so the rewritten line is still a sentence.
        if edit.kind != .replace, let carried {
            if let last = body.lastIndex(where: { !$0.isTarget }),
               removal.lowerBound > bounds.lower,
               removal.upperBound - 1 >= upper,
               trailingPunctuation(of: body[last].text) == nil,
               carried != "," {
                body[last] = FragmentPiece(text: body[last].text + String(carried), isTarget: body[last].isTarget)
            }
        }

        // Cutting "I, like, think" must not leave "I, think".
        if edit.kind != .replace, carried == ",",
           let last = body.lastIndex(where: { $0.text.hasSuffix(",") }),
           last == removal.lowerBound - bounds.lower - 1 {
            body[last] = FragmentPiece(text: String(body[last].text.dropLast()), isTarget: body[last].isTarget)
        }

        if startedSentence, edit.kind != .replace,
           let first = body.firstIndex(where: { !$0.text.isEmpty }) {
            body[first] = FragmentPiece(text: capitalizedFirst(body[first].text), isTarget: body[first].isTarget)
        }

        var pieces: [FragmentPiece] = []
        if bounds.truncatedLeft {
            pieces.append(FragmentPiece(text: "\u{2026}", isTarget: false))
        }
        pieces.append(contentsOf: body)
        if bounds.truncatedRight {
            pieces.append(FragmentPiece(text: "\u{2026}", isTarget: false))
        }

        // A rewrite identical to the original teaches nothing.
        let original = fragment(tokenRange: tokenRange, radius: radius, in: tokens).map(\.text)
        guard pieces.map(\.text) != original else { return nil }

        return pieces
    }

    private static func trailingPunctuation(of raw: String) -> Character? {
        guard let last = raw.last, ",.!?;:\u{2026}".contains(last) else { return nil }
        return last
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + String(text.dropFirst())
    }

    // MARK: Context predicates

    private static func token(_ index: Int, in tokens: [SwapToken]) -> String? {
        guard tokens.indices.contains(index) else { return nil }
        return tokens[index].text
    }

    private static func isSentenceStart(_ index: Int, _ tokens: [SwapToken]) -> Bool {
        guard index > 0 else { return true }
        guard tokens.indices.contains(index) else { return false }
        let previous = tokens[index - 1]
        return previous.endsSentence || tokens[index].start - previous.end > 0.9
    }

    private static func isSentenceEnd(_ index: Int, _ tokens: [SwapToken]) -> Bool {
        guard index < tokens.count - 1 else { return true }
        guard index >= 0 else { return false }
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

import Foundation

/// Words the on-device model invented for the workout, validated and persisted
/// next to the FSRS state. UserDefaults rather than SwiftData: a few hundred
/// small values, readable off the main actor while picking, nothing worth
/// syncing or migrating.
nonisolated struct GeneratedVocabStore: @unchecked Sendable {
    static let standard = GeneratedVocabStore(defaults: .standard)

    private let defaults: UserDefaults
    private let entriesKey = "vocabChallenge.generated.v1"
    private let seenKey = "vocabChallenge.generatedSeen.v1"

    /// Oldest generated words fall off once the store outgrows this.
    private static let capacity = 200
    /// Every word ever accepted or offered, so the model never repeats itself.
    private static let seenCapacity = 600

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entries() -> [VocabLexiconEntry] {
        guard let data = defaults.data(forKey: entriesKey) else { return [] }
        return (try? JSONDecoder().decode([VocabLexiconEntry].self, from: data)) ?? []
    }

    func entry(for word: String) -> VocabLexiconEntry? {
        let key = word.lowercased()
        return entries().first { $0.word.lowercased() == key }
    }

    func contains(_ word: String) -> Bool {
        entry(for: word) != nil
    }

    /// Appends a validated entry, dropping duplicates and the oldest overflow.
    func append(_ entry: VocabLexiconEntry) {
        var current = entries()
        let key = entry.word.lowercased()
        guard !current.contains(where: { $0.word.lowercased() == key }) else { return }
        current.append(entry)
        if current.count > Self.capacity {
            current.removeFirst(current.count - Self.capacity)
        }
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: entriesKey)
        }
        markSeen([entry.word])
    }

    /// Lowercased keys of everything in the store plus everything ever seen,
    /// for exclusion sets.
    func knownKeys() -> Set<String> {
        var keys = Set(entries().map { $0.word.lowercased() })
        keys.formUnion(seenKeys())
        return keys
    }

    private func markSeen(_ words: [String]) {
        var seen = seenKeys()
        for word in words where !seen.contains(word.lowercased()) {
            seen.insert(word.lowercased())
        }
        var ordered = Array(seen)
        if ordered.count > Self.seenCapacity {
            // The set loses insertion order; trimming arbitrary members is
            // fine — the ring only exists to bound growth.
            ordered.removeFirst(ordered.count - Self.seenCapacity)
        }
        defaults.set(ordered, forKey: seenKey)
    }

    private func seenKeys() -> Set<String> {
        Set(defaults.stringArray(forKey: seenKey) ?? [])
    }
}

/// Turns raw model output into entries safe enough to spotlight. Pure and
/// nonisolated so tests can hammer it without a service.
nonisolated enum FreshWordSanitizer {
    /// Parses `WORD | gloss | prompt` lines from model output, keeping only
    /// entries that would survive WordSafety on their own.
    static func sanitize(
        _ output: String,
        level: Int,
        excluding knownKeys: Set<String>
    ) -> [VocabLexiconEntry] {
        let tier = min(2, max(0, level))
        var kept: [VocabLexiconEntry] = []
        var taken: Set<String> = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            line = line
                .trimmingCharacters(in: CharacterSet(charactersIn: "*`•-"))
                .trimmingCharacters(in: .whitespaces)
            // Numbered lists are common model manners; strip "1." prefixes.
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber) {
                line = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            guard let entry = parse(line: line, level: tier) else { continue }
            let key = entry.word.lowercased()
            if taken.contains(key) || knownKeys.contains(key) {
                continue
            }
            taken.insert(key)
            kept.append(entry)
        }
        return kept
    }

    private static func parse(line: String, level: Int) -> VocabLexiconEntry? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 else { return nil }
        let word = normalize(clean(parts[0]))
        guard isShapedLikeAWord(word) else { return nil }
        guard WordSafety.allowsForChallenge(word) else { return nil }
        let gloss = clean(parts[1])
        let prompt = clean(parts[2])
        guard (4...120).contains(gloss.count), (4...140).contains(prompt.count) else { return nil }
        // Definitions that merely echo the headword teach nothing.
        guard !gloss.lowercased().contains(word.lowercased()) else { return nil }
        return VocabLexiconEntry(word: word, gloss: gloss, prompt: prompt, level: level)
    }

    /// Strays from markdown-flavored output.
    private static func clean(_ part: String) -> String {
        part.trimmingCharacters(in: CharacterSet(charactersIn: "*`•\""))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Display form: first letter capitalized, rest lowercased.
    private static func normalize(_ word: String) -> String {
        let lowered = word.lowercased()
        guard let first = lowered.first else { return lowered }
        return first.uppercased() + lowered.dropFirst()
    }

    /// Single token, plain letters — no spaces, digits, hyphens, apostrophes.
    /// The inflection matcher works best on simple stems, and multi-word
    /// "vocabulary" never highlights cleanly in a transcript.
    private static func isShapedLikeAWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        guard (3...18).contains(word.count) else { return false }
        return word.allSatisfy { $0.isLetter && $0.isASCII }
    }
}

/// Keeps the intro pool from running dry: asks the on-device model for novel
/// words at the user's chosen difficulty and files the ones that survive
/// validation. Every failure path degrades silently — the curated lexicon has
/// always been the fallback and still is.
@MainActor
enum VocabFreshWordGenerator {
    /// One refill attempt at most every six hours.
    private static let throttleInterval: TimeInterval = 6 * 60 * 60
    private static let throttleKey = "vocabChallenge.freshRefillAt.v1"
    /// Refill once live stock drops below this many candidates.
    private static let bufferTarget = 10
    private static let requestCount = 8

    static func refillIfNeeded(
        preferences: VocabChallengePreferences,
        llmService: LLMService,
        now: Date = Date(),
        store: GeneratedVocabStore = .standard,
        defaults: UserDefaults = .standard
    ) async {
        guard preferences.isEnabled, preferences.introduceNew else { return }
        guard llmService.isAvailable else { return }
        guard store.entries().count < bufferTarget else { return }

        let lastRefill = defaults.double(forKey: throttleKey)
        let sinceLastRefill = now.timeIntervalSinceReferenceDate - lastRefill
        if lastRefill > 0, sinceLastRefill < throttleInterval { return }
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: throttleKey)

        let level = preferences.resolvedIntroLevel
        let output = await llmService.generateText(
            prompt: Self.request(level: level, recentKeys: recentKeys(preferences: preferences, store: store)),
            systemPrompt: Self.systemPrompt
        )
        guard let output else { return }

        // Everything that must never come back twice: curated words, anything
        // previously generated or offered, the user's own lists, banned tokens.
        var excluded = DefaultVocabLexicon.keys
        excluded.formUnion(store.knownKeys())
        excluded.formUnion(preferences.vocabWords.map { $0.lowercased() })
        excluded.formUnion(preferences.dictionaryWords.map { $0.lowercased() })
        excluded.formUnion(preferences.extraBanned.map { $0.lowercased() })
        excluded.formUnion(preferences.userName.split { !$0.isLetter }.map { $0.lowercased() })

        let fresh = FreshWordSanitizer.sanitize(output, level: level, excluding: excluded)
        for entry in fresh {
            store.append(entry)
        }
    }

    private static let systemPrompt = """
    You expand the vocabulary of a public-speaking practice app. You answer \
    with plain formatted lines only — no markdown, no commentary.
    """

    private static func request(level: Int, recentKeys: [String]) -> String {
        let tierName = switch level {
        case 0: "accessible everyday English"
        case 1: "sharp professional vocabulary"
        default: "elevated literary vocabulary"
        }
        var lines = """
        Suggest \(requestCount) English words for daily speaking practice. Difficulty: \(tierName).
        Rules: single words, letters only. No phrases, names, brands, profanity, or filler words.
        Output EXACTLY \(requestCount) lines, each in this format:
        WORD | one-sentence definition | Use-it challenge about a speaking moment.
        """
        if !recentKeys.isEmpty {
            lines += "\nAvoid these already-used words: \(recentKeys.joined(separator: ", "))."
        }
        return lines
    }

    /// Recently graded words plus current stock, capped so the prompt stays
    /// small enough for the local model's context window.
    private static func recentKeys(
        preferences: VocabChallengePreferences,
        store: GeneratedVocabStore
    ) -> [String] {
        var keys = Array(preferences.vocabWords.prefix(6))
        keys.append(contentsOf: Array(preferences.dictionaryWords.prefix(4)))
        keys.append(contentsOf: store.entries().suffix(8).map(\.word))
        return Array(Set(keys.map { $0.lowercased() }).sorted().prefix(20))
    }
}

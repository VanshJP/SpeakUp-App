import Foundation
import NaturalLanguage

// MARK: - Input

nonisolated struct LexiconSessionInput: Sendable {
    let date: Date
    let transcript: String
    let fillerCounts: [String: Int]
    let overallScore: Int?
    let category: String?

    init(
        date: Date,
        transcript: String,
        fillerCounts: [String: Int] = [:],
        overallScore: Int? = nil,
        category: String? = nil
    ) {
        self.date = date
        self.transcript = transcript
        self.fillerCounts = fillerCounts
        self.overallScore = overallScore
        self.category = category
    }
}

// MARK: - Output models

nonisolated enum UsageDirection: String, Sendable {
    case rising
    case steady
    case falling
}

nonisolated enum CrutchCategory: String, Sendable {
    case filler
    case hedge
    case intensifier
    case vague
    case structural

    var label: String {
        switch self {
        case .filler: return "Filler"
        case .hedge: return "Hedge"
        case .intensifier: return "Softener"
        case .vague: return "Vague"
        case .structural: return "Repeated frame"
        }
    }
}

nonisolated struct LexiconCategoryStat: Identifiable, Hashable, Sendable {
    let category: String
    let sessions: Int
    let averageScore: Int?
    let weakRate: Double
    let powerRate: Double
    let topCrutch: String?

    var id: String { category }
}

nonisolated struct WordUsageSummary: Identifiable, Hashable, Sendable {
    let word: String
    let count: Int
    let recentCount: Int
    let direction: UsageDirection
    let category: CrutchCategory?
    let isPowerVerb: Bool

    var id: String { word }
}

nonisolated struct LanguageTrendPoint: Identifiable, Hashable, Sendable {
    let weekStart: Date
    let weakRate: Double
    let powerRate: Double
    let sessions: Int

    var id: Date { weekStart }
}

nonisolated struct InterviewReadiness: Sendable {
    nonisolated struct Component: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let value: Int
        let icon: String
        let hint: String
    }

    let score: Int
    let components: [Component]

    func value(named name: String) -> Int? {
        components.first { $0.name == name }?.value
    }

    var weakest: Component? {
        components.min { $0.value < $1.value }
    }
}

nonisolated struct LexiconSuggestion: Identifiable, Hashable, Sendable {
    nonisolated enum Tone: String, Sendable {
        case focus
        case positive
        case warning
    }

    let title: String
    let detail: String
    let icon: String
    let tone: Tone

    var id: String { title + detail }
}

nonisolated struct LexiconProfile: Sendable {
    let sessionCount: Int
    let analyzedSessionCount: Int
    let totalWords: Int
    let weakRate: Double
    let powerRate: Double
    let crutchWords: [WordUsageSummary]
    let contentWords: [WordUsageSummary]
    let powerVerbs: [WordUsageSummary]
    let categoryBreakdown: [LexiconCategoryStat]
    let trendPoints: [LanguageTrendPoint]
    let weakRateDelta: Double
    let powerRateDelta: Double
    let interviewReadiness: InterviewReadiness?
    let suggestions: [LexiconSuggestion]

    static let empty = LexiconProfile(
        sessionCount: 0,
        analyzedSessionCount: 0,
        totalWords: 0,
        weakRate: 0,
        powerRate: 0,
        crutchWords: [],
        contentWords: [],
        powerVerbs: [],
        categoryBreakdown: [],
        trendPoints: [],
        weakRateDelta: 0,
        powerRateDelta: 0,
        interviewReadiness: nil,
        suggestions: []
    )

    var hasData: Bool {
        analyzedSessionCount > 0 && totalWords > 20
    }
}

// MARK: - Session-level hits

/// One crutch word inside a single recording: what it was, how often it
/// landed, where it happened, and — when the timed transcription is available
/// — what to say instead *in that sentence*, not in general.
nonisolated struct SessionWordHit: Identifiable, Hashable, Sendable {
    let word: String
    let category: CrutchCategory
    let count: Int
    let timestamps: [TimeInterval]
    /// Context-derived coaching moments, strongest suggestion pattern first.
    /// Empty for hand-built hits; those fall back to the static map below.
    var occurrences: [WordSwapOccurrence]

    var id: String { word }

    init(
        word: String,
        category: CrutchCategory,
        count: Int,
        timestamps: [TimeInterval],
        occurrences: [WordSwapOccurrence] = []
    ) {
        self.word = word
        self.category = category
        self.count = count
        self.timestamps = timestamps
        self.occurrences = occurrences
    }

    /// Up to three ranked swaps: the dominant contextual replacement, distinct
    /// alternates from other occurrences' patterns, then the winner's own
    /// fallbacks. Without occurrences this falls back to the alternatives map,
    /// then category advice.
    var swaps: [String] {
        var contextual = WordSwapSuggester.dominantReplacements(in: occurrences)
        if !contextual.isEmpty {
            // The winner's own fallbacks: the remaining options on the
            // occurrence that produced it, ranked behind its primary swap.
            if let winner = primarySwap,
               let source = occurrences.first(where: { $0.best?.replacement == winner.replacement }) {
                for option in source.options.dropFirst() where contextual.count < 3 {
                    if !contextual.contains(option.replacement) {
                        contextual.append(option.replacement)
                    }
                }
            }
            return contextual
        }

        let own = LexiconInsightsEngine.alternatives[word] ?? []
        if !own.isEmpty { return own }
        switch category {
        case .filler: return ["a silent pause"]
        case .hedge: return ["state it directly"]
        case .intensifier: return ["one stronger word", "cut it"]
        case .vague: return ["name the specifics"]
        case .structural: return ["vary the opening", "name the list once"]
        }
    }

    /// The winning swap with its "when/why" cue, for emphasized rendering.
    var primarySwap: WordSwapOption? {
        WordSwapSuggester.primaryOption(in: occurrences)
    }

    /// Sentence fragment around the occurrence whose suggestion won.
    var exampleFragment: [FragmentPiece]? {
        guard let primarySwap else { return occurrences.first?.fragment }
        return (occurrences.first(where: { $0.best?.replacement == primarySwap.replacement })
                ?? occurrences.first)?.fragment
    }
}

// MARK: - Engine

nonisolated enum LexiconInsightsEngine {

    // MARK: Word lists

    static let hedgePhrases: [String] = [
        "i think", "i guess", "i suppose", "i feel like", "i believe",
        "kind of", "sort of", "you know", "i mean", "or something",
        "a little bit", "not really sure", "i'm not sure",
        "more or less", "to be honest", "if that makes sense",
        "a lot"
    ]

    static let intensifierWords: Set<String> = [
        "very", "really", "just", "actually", "basically", "literally",
        "totally", "honestly", "seriously", "simply", "completely",
        "absolutely", "definitely", "probably", "maybe", "perhaps",
        "somewhat", "quite", "super", "extremely", "truly"
    ]

    static let vagueWords: Set<String> = [
        "things", "stuff", "something", "somehow", "whatever",
        "kinda", "sorta", "etc"
    ]

    static let powerVerbs: Set<String> = [
        "led", "leads", "leading", "built", "builds", "building",
        "created", "creates", "creating", "launched", "launches", "launching",
        "shipped", "ships", "shipping", "managed", "manages", "managing",
        "owned", "owning", "drove", "drives", "driving",
        "delivered", "delivers", "delivering", "achieved", "achieves", "achieving",
        "improved", "improves", "improving", "increased", "increases", "increasing",
        "reduced", "reduces", "reducing", "grew", "grows", "growing",
        "scaled", "scales", "scaling", "designed", "designs", "designing",
        "developed", "develops", "developing", "implemented", "implements", "implementing",
        "negotiated", "negotiates", "negotiating", "mentored", "mentors", "mentoring",
        "coached", "coaches", "coaching", "hired", "recruited", "trained",
        "analyzed", "analyzes", "analyzing", "researched", "presented", "presents",
        "presenting", "sold", "selling", "won", "winning", "saved",
        "cutting", "automated", "automates", "automating", "migrated", "streamlined",
        "organized", "coordinated", "founded", "founding", "pioneered",
        "transformed", "resolved", "optimized", "exceeded", "secured", "executed",
        "executing", "spearheaded", "directed", "supervised", "budgeted", "architected",
        "deployed", "deploying", "refactored", "rebuilt", "overhauled", "established",
        "establishes", "establishing"
    ]

    /// Words that never become a "topic you return to".
    ///
    /// Blast radius is exactly `contentWords`: by the time this check runs,
    /// fillers, hedges, intensifiers, vague nouns and impact verbs have each
    /// been counted and `continue`d, so nothing here can suppress a crutch or
    /// an impact verb. The corollary is a trap — a word listed both here and
    /// in `intensifierWords` / `vagueWords` / `powerVerbs` silently takes the
    /// earlier branch, so this list must stay disjoint from those.
    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "so", "because", "if", "then", "than",
        "that", "this", "these", "those", "i", "me", "my", "mine", "we", "us", "our",
        "you", "your", "he", "him", "his", "she", "her", "it", "its", "they", "them",
        "their", "is", "am", "are", "was", "were", "be", "been", "being", "do", "does",
        "did", "have", "has", "had", "will", "would", "can", "could", "should", "shall",
        "may", "might", "must", "to", "of", "in", "on", "at", "for", "with", "from",
        "by", "about", "as", "into", "like", "get", "got", "gonna", "wanna", "gotta",
        "go", "going", "went", "when", "what", "which", "who", "whom", "how", "why",
        "where", "not", "no", "yes", "yeah", "okay", "ok", "right", "well", "there",
        "here", "up", "down", "out", "off", "over", "under", "again", "also", "too",
        "even", "still", "back", "now", "one", "two", "all", "any", "some", "more",
        "most", "other",
        // Contractions. `NLTokenizer` emits "i'm" and "wasn't" as single
        // tokens and `normalize` only strips punctuation from the ends, so the
        // apostrophe survives and the stems above never match. Untreated they
        // outranked real subjects in "Topics you return to".
        "i'm", "i've", "i'll", "i'd", "we're", "we've", "we'll", "we'd",
        "you're", "you've", "you'll", "you'd", "they're", "they've", "they'll",
        "he's", "she's", "it's", "that's", "there's", "here's", "what's",
        "who's", "let's", "isn't", "aren't", "wasn't", "weren't", "don't",
        "doesn't", "didn't", "can't", "cannot", "couldn't", "won't", "wouldn't",
        "shouldn't", "hasn't", "haven't", "hadn't", "ain't",
        // Speech verbs that frame a topic without being one — "I *think* the
        // migration mattered" is about the migration. Deliberately narrow:
        // "make", "take" and "use" are NOT here, because "make films" and
        // "take deposits" are exactly the subjects this list must not eat.
        "want", "wants", "wanted", "know", "knows", "knew", "think", "thinks",
        "thought", "say", "says", "said", "tell", "tells", "told"
    ]

    static let alternatives: [String: [String]] = [
        "um": ["pause silently", "breathe through it", "close mouth, one beat"],
        "uh": ["pause silently", "breathe through it"],
        "like": ["a pause", "\u{201C}for example\u{201D}", "\u{201C}such as\u{201D}", "\u{201C}roughly\u{201D} before numbers", "cut entirely"],
        "you know": ["a pause", "cut it entirely", "\u{201C}right?\u{201D} once at most"],
        "i mean": ["a pause", "\u{201C}that is\u{201D}", "\u{201C}put differently\u{201D}"],
        "i think": ["\u{201C}I believe\u{201D}", "state it directly", "\u{201C}My read is\u{201D}", "\u{201C}I'd argue\u{201D}"],
        "i guess": ["own the claim", "\u{201C}I'm confident\u{201D}", "cut it entirely"],
        "i suppose": ["own the claim", "cut it entirely"],
        "i feel like": ["\u{201C}My view is\u{201D}", "\u{201C}The evidence says\u{201D}", "\u{201C}I've seen\u{201D}"],
        "i believe": ["\u{201C}I know\u{201D}", "\u{201C}I've proven\u{201D}", "state it directly"],
        "kind of": ["drop it", "\u{201C}roughly\u{201D} for numbers only", "\u{201C}somewhat\u{201D} sparingly", "be specific instead"],
        "sort of": ["drop it", "\u{201C}roughly\u{201D} for numbers only", "be specific instead"],
        "or something": ["the precise thing", "end the sentence there"],
        "a little bit": ["the actual amount", "\u{201C}slightly\u{201D}", "drop it"],
        "not really sure": ["\u{201C}Let me think out loud\u{201D}", "commit to your best answer"],
        "to be honest": ["cut it, the claim should carry itself", "\u{201C}Frankly\u{201D}, once"],
        "if that makes sense": ["pause and check eyes instead", "end cleanly"],
        "just": ["cut it", "\u{201C}only\u{201D} when counting matters", "drop \u{201C}just\u{201D} entirely"],
        "really": ["one strong adjective (\u{201C}significant\u{201D})", "cut it", "\u{201C}genuinely\u{201D} sparingly"],
        "very": ["one strong word (\u{201C}crucial\u{201D}, \u{201C}vital\u{201D})", "\u{201C}highly\u{201D}", "quantify instead: \u{201C}3\u{00D7} faster\u{201D}"],
        "actually": ["cut it", "\u{201C}in fact\u{201D} when correcting", "\u{201C}as it turns out\u{201D}, once"],
        "basically": ["cut it", "\u{201C}in short\u{201D}, once, at the end", "\u{201C}the core idea is\u{201D}"],
        "literally": ["cut it unless it literally happened", "\u{201C}exactly\u{201D} with numbers"],
        "honestly": ["let the claim carry itself", "cut it", "\u{201C}Frankly\u{201D}, once"],
        "seriously": ["cut it", "state the fact plainly"],
        "totally": ["\u{201C}entirely\u{201D}", "the specific degree", "cut it"],
        "simply": ["cut it", "\u{201C}just\u{201D} too"],
        "completely": ["\u{201C}entirely\u{201D}", "the specific outcome"],
        "absolutely": ["\u{201C}Yes.\u{201D} full stop", "\u{201C}without question\u{201D}"],
        "definitely": ["commit via past results", "\u{201C}certainly\u{201D}", "cut it"],
        "probably": ["\u{201C}likely\u{201D}", "give odds: \u{201C}9 times in 10\u{201D}"],
        "maybe": ["\u{201C}possibly\u{201D} + a condition", "commit or set the test"],
        "perhaps": ["\u{201C}likely\u{201D}", "commit to a position"],
        "somewhat": ["the exact degree", "drop it"],
        "quite": ["drop it", "the exact degree"],
        "super": ["the strong adjective itself (\u{201C}impactful\u{201D})"],
        "extremely": ["the strong adjective itself", "quantify instead"],
        "truly": ["cut it", "\u{201C}genuinely\u{201D} with feeling words only"],
        "things": ["name the specific things", "\u{201C}three factors\u{201D} + name them"],
        "stuff": ["name the specifics", "\u{201C}the details\u{201D} + give them"],
        "something": ["the exact thing you did", "name it"],
        "somehow": ["the actual mechanism", "cut it"],
        "whatever": ["the precise term", "cut it"],
        "kinda": ["\u{201C}kind of\u{201D}, then drop that too", "be specific"],
        "sorta": ["\u{201C}sort of\u{201D}, then drop that too", "be specific"],
        "etc": ["name the last item", "\u{201C}and two more worth naming\u{201D}"],
        "got": ["received", "earned", "secured", "obtained"]
    ]

    // MARK: Entry point

    static func profile(from sessions: [LexiconSessionInput]) -> LexiconProfile {
        let valid = sessions
            .filter { !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.date < $1.date }

        guard !valid.isEmpty else { return .empty }

        let midIndex = valid.count / 2
        let hasBothHalves = valid.count > 1 && midIndex > 0 && midIndex < valid.count

        var usageCounts: [String: Int] = [:]
        var usageRecent: [String: Int] = [:]
        var categories: [String: CrutchCategory] = [:]
        var powerFlags: Set<String> = []

        var weeklyTokens: [Date: Int] = [:]
        var weeklyWeak: [Date: Int] = [:]
        var weeklyPower: [Date: Int] = [:]
        var weeklySessions: [Date: Int] = [:]

        var earlyTokens = 0
        var recentTokens = 0
        var earlyWeak = 0
        var recentWeak = 0
        var earlyPower = 0
        var recentPower = 0

        var totalTokens = 0
        var totalFillers = 0
        var totalSofteners = 0
        var totalPower = 0
        var totalNumericTokens = 0
        var scores: [Int] = []
        let calendar = Calendar.current

        var categoryTokens: [String: Int] = [:]
        var categoryWeak: [String: Int] = [:]
        var categoryPower: [String: Int] = [:]
        var categorySessions: [String: Int] = [:]
        var categoryScores: [String: [Int]] = [:]
        var categoryTopCrutch: [String: (word: String, count: Int)] = [:]

        func bump(_ word: String, _ count: Int, isRecent: Bool) {
            usageCounts[word, default: 0] += count
            if isRecent {
                usageRecent[word, default: 0] += count
            }
        }

        for (index, session) in valid.enumerated() {
            let isRecent = hasBothHalves && index >= midIndex
            let lowered = session.transcript.lowercased()
            let words = tokenize(lowered)
            let tokenCount = words.count

            totalTokens += tokenCount
            if isRecent {
                recentTokens += tokenCount
            } else if hasBothHalves {
                earlyTokens += tokenCount
            }

            if let score = session.overallScore {
                scores.append(score)
            }

            let weekStart = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start ?? session.date
            weeklySessions[weekStart, default: 0] += 1

            var sessionFillers = 0
            var sessionSofteners = 0
            var sessionPower = 0
            var sessionNumerics = 0
            var topNamedHabit: (word: String, count: Int)?

            func noteHabit(_ word: String, _ count: Int) {
                guard count > 0 else { return }
                if let current = topNamedHabit {
                    if count > current.count { topNamedHabit = (word, count) }
                } else {
                    topNamedHabit = (word, count)
                }
            }

            if !session.fillerCounts.isEmpty {
                for (word, count) in session.fillerCounts where count > 0 {
                    let normalized = normalize(word)
                    guard !normalized.isEmpty else { continue }
                    bump(normalized, count, isRecent: isRecent)
                    categories[normalized] = .filler
                    sessionFillers += count
                    noteHabit(normalized, count)
                }
            }

            for word in words {
                if word.contains(where: { $0.isNumber }) {
                    sessionNumerics += 1
                    continue
                }

                if !session.fillerCounts.isEmpty && session.fillerCounts[word] != nil {
                    continue
                }

                if session.fillerCounts.isEmpty && FillerWordList.isFillerWord(word) {
                    bump(word, 1, isRecent: isRecent)
                    categories[word] = .filler
                    sessionFillers += 1
                    noteHabit(word, 1)
                    continue
                }

                if intensifierWords.contains(word) {
                    bump(word, 1, isRecent: isRecent)
                    if categories[word] == nil { categories[word] = .intensifier }
                    sessionSofteners += 1
                    continue
                }

                if vagueWords.contains(word) {
                    bump(word, 1, isRecent: isRecent)
                    if categories[word] == nil { categories[word] = .vague }
                    sessionSofteners += 1
                    continue
                }

                if powerVerbs.contains(word) {
                    bump(word, 1, isRecent: isRecent)
                    powerFlags.insert(word)
                    sessionPower += 1
                    continue
                }

                if stopwords.contains(word) || word.count < 3 {
                    continue
                }

                bump(word, 1, isRecent: isRecent)
            }

            for phrase in hedgePhrases {
                let hits = countPhraseOccurrences(phrase, in: lowered)
                guard hits > 0 else { continue }
                bump(phrase, hits, isRecent: isRecent)
                if categories[phrase] == nil { categories[phrase] = .hedge }
                sessionSofteners += hits
                noteHabit(phrase, hits)
            }

            let sessionWeak = sessionFillers + sessionSofteners

            weeklyTokens[weekStart, default: 0] += tokenCount
            weeklyWeak[weekStart, default: 0] += sessionWeak
            weeklyPower[weekStart, default: 0] += sessionPower

            if let category = session.category?.trimmingCharacters(in: .whitespacesAndNewlines),
               !category.isEmpty {
                categoryTokens[category, default: 0] += tokenCount
                categoryWeak[category, default: 0] += sessionWeak
                categoryPower[category, default: 0] += sessionPower
                categorySessions[category, default: 0] += 1
                if let score = session.overallScore {
                    categoryScores[category, default: []].append(score)
                }
                if let habit = topNamedHabit {
                    if let existing = categoryTopCrutch[category], existing.count >= habit.count {
                        // keep the stronger offender
                    } else {
                        categoryTopCrutch[category] = habit
                    }
                }
            }

            totalFillers += sessionFillers
            totalSofteners += sessionSofteners
            totalPower += sessionPower
            totalNumericTokens += sessionNumerics

            if isRecent {
                recentWeak += sessionWeak
                recentPower += sessionPower
            } else if hasBothHalves {
                earlyWeak += sessionWeak
                earlyPower += sessionPower
            }
        }

        func rate(_ count: Int, _ tokens: Int) -> Double {
            guard tokens > 0 else { return 0 }
            return Double(count) / Double(tokens) * 100
        }

        let directionFor: (Int, Int) -> UsageDirection = { count, recent in
            guard hasBothHalves, count >= 3 else { return .steady }
            let share = Double(recent) / Double(count)
            if share > 0.62 { return .rising }
            if share < 0.38 { return .falling }
            return .steady
        }

        let allSummaries: [WordUsageSummary] = usageCounts.map { word, count in
            let recent = usageRecent[word] ?? 0
            return WordUsageSummary(
                word: word,
                count: count,
                recentCount: recent,
                direction: directionFor(count, recent),
                category: categories[word],
                isPowerVerb: powerFlags.contains(word)
            )
        }

        let crutchWords = allSummaries
            .filter { $0.category != nil }
            .sorted { ($0.count, $0.word) > ($1.count, $1.word) }

        let powerVerbsList = allSummaries
            .filter(\.isPowerVerb)
            .sorted { ($0.count, $0.word) > ($1.count, $1.word) }

        let contentWords = Array(
            allSummaries
                .filter { $0.category == nil && !$0.isPowerVerb }
                .sorted { ($0.count, $0.word) > ($1.count, $1.word) }
                .prefix(12)
        )

        let weakRateDelta = rate(recentWeak, recentTokens) - rate(earlyWeak, earlyTokens)
        let powerRateDelta = rate(recentPower, recentTokens) - rate(earlyPower, earlyTokens)

        let trendPoints = weeklySessions.keys.sorted().compactMap { day -> LanguageTrendPoint? in
            guard let tokens = weeklyTokens[day], tokens > 0 else { return nil }
            return LanguageTrendPoint(
                weekStart: day,
                weakRate: rate(weeklyWeak[day] ?? 0, tokens),
                powerRate: rate(weeklyPower[day] ?? 0, tokens),
                sessions: weeklySessions[day] ?? 0
            )
        }

        let categoryBreakdown = categorySessions.keys.sorted().map { category -> LexiconCategoryStat in
            let tokens = categoryTokens[category] ?? 0
            let categoryScoreList = categoryScores[category] ?? []
            return LexiconCategoryStat(
                category: category,
                sessions: categorySessions[category] ?? 0,
                averageScore: categoryScoreList.isEmpty
                    ? nil
                    : Int((Double(categoryScoreList.reduce(0, +)) / Double(categoryScoreList.count)).rounded()),
                weakRate: rate(categoryWeak[category] ?? 0, tokens),
                powerRate: rate(categoryPower[category] ?? 0, tokens),
                topCrutch: categoryTopCrutch[category]?.word
            )
        }
        .sorted { $0.sessions > $1.sessions }

        let analyzedCount = valid.count
        let readiness = buildReadiness(
            analyzedCount: analyzedCount,
            totalTokens: totalTokens,
            totalFillers: totalFillers,
            totalSofteners: totalSofteners,
            totalPower: totalPower,
            totalNumericTokens: totalNumericTokens,
            scores: scores
        )

        let suggestions = makeSuggestions(
            crutchWords: crutchWords,
            powerVerbs: powerVerbsList,
            totalPowerUses: totalPower,
            analyzedCount: analyzedCount,
            weakRateDelta: weakRateDelta,
            readiness: readiness
        )

        return LexiconProfile(
            sessionCount: sessions.count,
            analyzedSessionCount: analyzedCount,
            totalWords: totalTokens,
            weakRate: rate(totalFillers + totalSofteners, totalTokens),
            powerRate: rate(totalPower, totalTokens),
            crutchWords: crutchWords,
            contentWords: contentWords,
            powerVerbs: powerVerbsList,
            categoryBreakdown: categoryBreakdown,
            trendPoints: trendPoints,
            weakRateDelta: weakRateDelta,
            powerRateDelta: powerRateDelta,
            interviewReadiness: readiness,
            suggestions: suggestions
        )
    }

    static func alternativesFor(_ word: String) -> [String]? {
        alternatives[normalize(word)]
    }

    /// Crutch hits for one recording, derived from its timed transcription so
    /// every occurrence carries a playable timestamp and a context-aware swap
    /// (see `WordSwapSuggester`). Pipeline-tagged fillers (`isFiller`) are
    /// authoritative; hedge phrases are matched longest-first and consume
    /// their tokens so "not really sure" never double-counts the "really"
    /// inside it. Sorted by count, then alphabetically for stability.
    static func sessionHits(from words: [TranscriptionWord]) -> [SessionWordHit] {
        let tokens = words.map { word -> SwapToken in
            let trimmed = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            return SwapToken(
                text: normalize(trimmed),
                raw: trimmed.isEmpty ? word.word : trimmed,
                start: word.start,
                end: word.end,
                isPipelineFiller: word.isFiller
            )
        }

        var consumed = Array(repeating: false, count: tokens.count)
        var counts: [String: Int] = [:]
        var categories: [String: CrutchCategory] = [:]
        var occurrenceRanges: [String: [Range<Int>]] = [:]

        func note(_ word: String, _ category: CrutchCategory, at range: Range<Int>) {
            counts[word, default: 0] += 1
            if categories[word] == nil { categories[word] = category }
            occurrenceRanges[word, default: []].append(range)
        }

        let phrases = hedgePhrases.sorted { $0.split(separator: " ").count > $1.split(separator: " ").count }
        for phrase in phrases {
            let parts = phrase.split(separator: " ").map(String.init)
            guard parts.count > 1 else { continue }

            var index = 0
            while index + parts.count <= tokens.count {
                defer { index += 1 }

                guard !consumed[index] else { continue }
                let window = Array(index..<index + parts.count)
                guard zip(window, parts).allSatisfy({ tokens[$0].text == $1 && !consumed[$0] }) else { continue }

                note(phrase, .hedge, at: index..<index + parts.count)
                for position in window {
                    consumed[position] = true
                }
                index += parts.count - 1
            }
        }

        for (offset, token) in tokens.enumerated() where !consumed[offset] {
            let text = token.text
            guard !text.isEmpty else { continue }

            if token.isPipelineFiller || FillerWordList.isFillerWord(text) {
                note(text, .filler, at: offset..<offset + 1)
            } else if intensifierWords.contains(text) {
                note(text, .intensifier, at: offset..<offset + 1)
            } else if vagueWords.contains(text) {
                note(text, .vague, at: offset..<offset + 1)
            }
        }

        // Structural repetition frames are coached via tip + plum transcript
        // highlights — not as word-swap rows (a frame is not a crutch word).

        return counts.map { word, count -> SessionWordHit in
            let category = categories[word] ?? .filler

            // Occurrences in play order so timestamps stay chronological.
            let ranges = (occurrenceRanges[word] ?? [])
                .sorted { tokens[$0.lowerBound].start < tokens[$1.lowerBound].start }
            let occurrences = ranges.map { range in
                WordSwapOccurrence(
                    timestamp: tokens[range.lowerBound].start,
                    fragment: WordSwapSuggester.fragment(tokenRange: range, radius: 6, in: tokens),
                    options: WordSwapSuggester.options(
                        for: word,
                        category: category,
                        tokenRange: range,
                        tokens: tokens
                    )
                )
            }

            return SessionWordHit(
                word: word,
                category: category,
                count: count,
                timestamps: occurrences.map(\.timestamp),
                occurrences: occurrences
            )
        }
        .sorted { ($0.count, $0.word) > ($1.count, $1.word) }
    }

    // MARK: - Readiness

    private static func buildReadiness(
        analyzedCount: Int,
        totalTokens: Int,
        totalFillers: Int,
        totalSofteners: Int,
        totalPower: Int,
        totalNumericTokens: Int,
        scores: [Int]
    ) -> InterviewReadiness {
        func rate(_ count: Int) -> Double {
            guard totalTokens > 0 else { return 0 }
            return Double(count) / Double(totalTokens) * 100
        }

        let fluency = piecewiseScore(rate(totalFillers), [
            (input: 0, score: 100),
            (input: 1, score: 92),
            (input: 3, score: 76),
            (input: 6, score: 54),
            (input: 10, score: 30),
            (input: 15, score: 12)
        ])

        let authority = piecewiseScore(rate(totalSofteners), [
            (input: 0, score: 100),
            (input: 2, score: 85),
            (input: 4, score: 68),
            (input: 8, score: 44),
            (input: 12, score: 24),
            (input: 18, score: 10)
        ])

        let impact = piecewiseScore(rate(totalPower), [
            (input: 0, score: 30),
            (input: 0.5, score: 50),
            (input: 1, score: 66),
            (input: 2, score: 80),
            (input: 3.5, score: 93),
            (input: 5, score: 98)
        ])

        let numericsPerSession = Double(totalNumericTokens) / Double(max(1, analyzedCount))
        let evidence = piecewiseScore(numericsPerSession, [
            (input: 0, score: 32),
            (input: 0.5, score: 55),
            (input: 1.5, score: 76),
            (input: 3, score: 88),
            (input: 6, score: 96)
        ])

        let avgTokens = Double(totalTokens) / Double(max(1, analyzedCount))
        let depth = piecewiseScore(avgTokens, [
            (input: 30, score: 25),
            (input: 60, score: 45),
            (input: 90, score: 62),
            (input: 130, score: 78),
            (input: 180, score: 88),
            (input: 250, score: 95)
        ])

        let consistency: Int
        if scores.count >= 2 {
            let mean = Double(scores.reduce(0, +)) / Double(scores.count)
            let variance = scores.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(scores.count)
            consistency = piecewiseScore(sqrt(variance), [
                (input: 0, score: 98),
                (input: 5, score: 86),
                (input: 10, score: 70),
                (input: 15, score: 52),
                (input: 25, score: 34)
            ])
        } else {
            consistency = 60
        }

        let weighted = Double(fluency) * 0.18
            + Double(authority) * 0.20
            + Double(impact) * 0.22
            + Double(evidence) * 0.12
            + Double(depth) * 0.14
            + Double(consistency) * 0.14

        let score = min(100, max(0, Int(weighted.rounded())))

        return InterviewReadiness(score: score, components: [
            InterviewReadiness.Component(
                name: "Impact verbs",
                value: impact,
                icon: "bolt.fill",
                hint: "Action verbs per 100 words"
            ),
            InterviewReadiness.Component(
                name: "Authority",
                value: authority,
                icon: "shield.fill",
                hint: "Hedges and softeners per 100 words"
            ),
            InterviewReadiness.Component(
                name: "Fluency",
                value: fluency,
                icon: "waveform",
                hint: "Filler words per 100 words"
            ),
            InterviewReadiness.Component(
                name: "Depth",
                value: depth,
                icon: "scalemass.fill",
                hint: "Average words per answer"
            ),
            InterviewReadiness.Component(
                name: "Evidence",
                value: evidence,
                icon: "number.square.fill",
                hint: "Numbers cited per answer"
            ),
            InterviewReadiness.Component(
                name: "Consistency",
                value: consistency,
                icon: "checkmark.seal.fill",
                hint: "Score stability across sessions"
            )
        ])
    }

    // MARK: - Suggestions

    private static func makeSuggestions(
        crutchWords: [WordUsageSummary],
        powerVerbs: [WordUsageSummary],
        totalPowerUses: Int,
        analyzedCount: Int,
        weakRateDelta: Double,
        readiness: InterviewReadiness?
    ) -> [LexiconSuggestion] {
        var suggestions: [LexiconSuggestion] = []

        if let top = crutchWords.first, top.count >= max(5, analyzedCount * 2) {
            let alts = alternatives[top.word] ?? ["a pause"]
            suggestions.append(LexiconSuggestion(
                title: "Retire \u{201C}\(top.word)\u{201D}",
                detail: "\(top.count) uses across \(analyzedCount) session\(analyzedCount == 1 ? "" : "s"). Try \(alts.joined(separator: ", ")).",
                icon: "text.badge.xmark",
                tone: .focus
            ))
        }

        if weakRateDelta > 1.5 {
            suggestions.append(LexiconSuggestion(
                title: "Weak language is creeping up",
                detail: String(
                    format: "+%.1f crutch words per 100 words vs your earlier sessions. Pick one phrase to drop this week.",
                    weakRateDelta
                ),
                icon: "arrow.up.right.circle",
                tone: .warning
            ))
        } else if weakRateDelta < -1.5 {
            suggestions.append(LexiconSuggestion(
                title: "Weak language is fading",
                detail: String(
                    format: "\u{2212}%.1f crutch words per 100 words vs earlier sessions. Keep it going.",
                    -weakRateDelta
                ),
                icon: "arrow.down.right.circle",
                tone: .positive
            ))
        }

        if let impact = readiness?.value(named: "Impact verbs"), impact < 55 {
            suggestions.append(LexiconSuggestion(
                title: "Swap weak verbs for action verbs",
                detail: "Replace \u{201C}I was involved in\u{201D} with \u{201C}I led\u{201D}, \u{201C}I built\u{201D}, \u{201C}I drove\u{201D}. Interviewers scan for ownership verbs.",
                icon: "bolt.badge.clock",
                tone: .focus
            ))
        }

        if let evidence = readiness?.value(named: "Evidence"), evidence < 55 {
            suggestions.append(LexiconSuggestion(
                title: "Add numbers to your answers",
                detail: "Quantified results land hardest: percentages, dollar amounts, team sizes, timelines. Aim for one number per answer.",
                icon: "number",
                tone: .focus
            ))
        }

        if let depth = readiness?.value(named: "Depth"), depth < 55 {
            suggestions.append(LexiconSuggestion(
                title: "Give answers room to breathe",
                detail: "Your answers run short. Use STAR: one sentence of situation, the task, what YOU did, the measurable result.",
                icon: "arrow.up.backward.and.arrow.down.forward",
                tone: .focus
            ))
        }

        if powerVerbs.count >= 2, let overused = powerVerbs.first,
           overused.count >= 4, totalPowerUses > 0,
           Double(overused.count) / Double(totalPowerUses) > 0.4 {
            let others = powerVerbs.dropFirst().prefix(3).map(\.word).joined(separator: ", ")
            suggestions.append(LexiconSuggestion(
                title: "Vary \u{201C}\(overused.word)\u{201D}",
                detail: overused.word.isEmpty ? "" : "\(overused.count) of your \(totalPowerUses) action-verb uses are \u{201C}\(overused.word)\u{201D}. Rotate in \(others.isEmpty ? "synonyms" : others).",
                icon: "repeat",
                tone: .warning
            ))
        }

        if let score = readiness?.score, score >= 80 {
            suggestions.append(LexiconSuggestion(
                title: "Interview ready",
                detail: "Language metrics are strong across the board. Keep sharp with timed STAR drills before the real thing.",
                icon: "checkmark.seal.fill",
                tone: .positive
            ))
        }

        return Array(suggestions.prefix(4))
    }

    // MARK: - Helpers

    static func piecewiseScore(_ value: Double, _ points: [(input: Double, score: Double)]) -> Int {
        guard !points.isEmpty else { return 50 }
        let sorted = points.sorted { $0.input < $1.input }
        guard value >= sorted[0].input else { return Int(sorted[0].score.rounded()) }
        guard value <= sorted[sorted.count - 1].input else {
            return Int(sorted[sorted.count - 1].score.rounded())
        }
        for index in 1..<sorted.count where value <= sorted[index].input {
            let a = sorted[index - 1]
            let b = sorted[index]
            let span = b.input - a.input
            let t = span > 0 ? (value - a.input) / span : 0
            return Int((a.score + t * (b.score - a.score)).rounded())
        }
        return Int(sorted[sorted.count - 1].score.rounded())
    }

    static func normalize(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = normalize(String(text[range]))
            if !word.isEmpty {
                words.append(word)
            }
            return true
        }
        return words
    }

    static func countPhraseOccurrences(_ phrase: String, in text: String) -> Int {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }
}

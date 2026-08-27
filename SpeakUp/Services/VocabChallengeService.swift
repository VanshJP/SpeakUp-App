import Foundation

/// Picks today's spotlight words, evaluates whether the user used them, and
/// never surfaces blocked or filler tokens.
nonisolated enum VocabChallengeService {
    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(fromDayStamp stamp: String, calendar: Calendar = .current) -> Date? {
        let parts = stamp.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    static func daySeed(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 366 + (parts.month ?? 0) * 31 + (parts.day ?? 0)
    }

    /// Words to fold into transcript vocab detection so introduced spotlight
    /// terms highlight even before the user adds them to the bank.
    static func detectionWords(
        preferences: VocabChallengePreferences,
        now: Date = Date(),
        store: VocabChallengeStore = .standard,
        generated: GeneratedVocabStore = .standard,
        usedCounts: [String: Int] = [:]
    ) -> [String] {
        todaysChallenge(
            preferences: preferences,
            usedCounts: usedCounts,
            now: now,
            store: store,
            generated: generated
        )?.words.map(\.text) ?? []
    }

    static func todaysChallenge(
        preferences: VocabChallengePreferences,
        usedCounts: [String: Int] = [:],
        now: Date = Date(),
        store: VocabChallengeStore = .standard,
        generated: GeneratedVocabStore = .standard,
        calendar: Calendar = .current
    ) -> DailyVocabChallenge? {
        guard preferences.isEnabled else { return nil }

        let stamp = dayStamp(now, calendar: calendar)
        let fingerprint = preferences.fingerprint
        let skipped = store.skipped(on: stamp)
        let seed = daySeed(now, calendar: calendar)

        if preferences.spacedReviewEnabled {
            settleUnusedWords(before: stamp, now: now, store: store, calendar: calendar)
        }
        let reviews = preferences.spacedReviewEnabled ? store.reviews() : [:]

        if let cached = store.cached(),
           cached.dayStamp == stamp,
           cached.fingerprint == fingerprint {
            let kept = cached.words.filter { !skipped.contains($0.text.lowercased()) }
            if kept.count == preferences.resolvedWordCount, !kept.isEmpty {
                return DailyVocabChallenge(dayStamp: stamp, words: kept, usedKeys: [], isCompleted: false)
            }
            let filled = fill(
                existing: kept,
                preferences: preferences,
                usedCounts: usedCounts,
                skipped: skipped,
                seed: seed,
                reviews: reviews,
                now: now,
                generated: generated
            )
            if filled.isEmpty { return emptyChallenge(dayStamp: stamp) }
            store.save(.init(dayStamp: stamp, fingerprint: fingerprint, words: filled))
            return DailyVocabChallenge(dayStamp: stamp, words: filled, usedKeys: [], isCompleted: false)
        }

        let picked = fill(
            existing: [],
            preferences: preferences,
            usedCounts: usedCounts,
            skipped: skipped,
            seed: seed,
            reviews: reviews,
            now: now,
            generated: generated
        )
        if picked.isEmpty { return emptyChallenge(dayStamp: stamp) }
        store.save(.init(dayStamp: stamp, fingerprint: fingerprint, words: picked))
        return DailyVocabChallenge(dayStamp: stamp, words: picked, usedKeys: [], isCompleted: false)
    }

    static func skip(
        _ word: String,
        preferences: VocabChallengePreferences,
        usedCounts: [String: Int] = [:],
        now: Date = Date(),
        store: VocabChallengeStore = .standard,
        calendar: Calendar = .current
    ) -> DailyVocabChallenge? {
        let stamp = dayStamp(now, calendar: calendar)
        // The rebuild below drops skipped words from the cached day on its own,
        // so the cache is only read here — for where the word was sitting.
        var previous: [VocabChallengeWord] = []
        if let cached = store.cached(), cached.dayStamp == stamp {
            previous = cached.words
        }
        let slot = previous.firstIndex { $0.id == word.lowercased() }
        store.skip(word, on: stamp)

        guard let refilled = todaysChallenge(
            preferences: preferences,
            usedCounts: usedCounts,
            now: now,
            store: store,
            calendar: calendar
        ) else { return nil }

        // The rebuild appends, so the replacement would otherwise land at the
        // bottom of the card and the row the user just tapped would jump away
        // from under their finger. Put it back in the skipped word's slot.
        guard let slot,
              refilled.words.count >= previous.count,
              slot < refilled.words.count - 1 else { return refilled }

        var words = refilled.words
        let replacement = words.removeLast()
        words.insert(replacement, at: slot)
        store.save(.init(dayStamp: stamp, fingerprint: preferences.fingerprint, words: words))

        var reordered = refilled
        reordered.words = words
        return reordered
    }

    static func evaluate(
        _ challenge: DailyVocabChallenge,
        transcripts: [String],
        usages: [VocabWordUsage]
    ) -> VocabChallengeEvaluation {
        guard !challenge.words.isEmpty else {
            return VocabChallengeEvaluation(used: [], missed: [])
        }

        var used: [String] = []
        var missed: [String] = []
        for word in challenge.words {
            let key = word.text.lowercased()
            let fromUsage = usages.contains {
                $0.word.lowercased() == key && $0.count > 0
            }
            let fromText = transcripts.contains { VocabMatcher.contains(word.text, in: $0) }
            if fromUsage || fromText {
                used.append(word.text)
            } else {
                missed.append(word.text)
            }
        }
        return VocabChallengeEvaluation(used: used, missed: missed)
    }

    static func applying(
        _ evaluation: VocabChallengeEvaluation,
        to challenge: DailyVocabChallenge
    ) -> DailyVocabChallenge {
        var next = challenge
        next.usedKeys = Set(evaluation.used.map { $0.lowercased() })
        next.isCompleted = evaluation.isComplete
        return next
    }

    // MARK: - Recording snapshots

    /// Rebuilds a challenge from a recording's stored snapshot. Empty word
    /// lists hide rather than render a hollow card.
    ///
    /// Takes plain values instead of `Recording` on purpose: models are
    /// MainActor-isolated, and this stays callable in tests without a store.
    static func challenge(
        dayStamp: String,
        words: [VocabChallengeWord]
    ) -> DailyVocabChallenge? {
        guard !words.isEmpty else { return nil }
        return DailyVocabChallenge(dayStamp: dayStamp, words: words, usedKeys: [], isCompleted: false)
    }

    /// The workout one recording is scored against.
    ///
    /// - Snapshot present → that day's pick. Authoritative even if the day
    ///   cache was later skipped or refilled elsewhere: the snapshot captured
    ///   what the user actually saw when they spoke.
    /// - No snapshot but recorded today → today's pick, preserving scoring for
    ///   takes analyzed by an app version older than snapshots.
    /// - No snapshot and recorded earlier → nil; the detail view hides the
    ///   card. Guessing would mislabel history loudly, so it stays silent.
    static func workout(
        forRecordingAt recordedOn: Date,
        snapshotDayStamp: String?,
        snapshotWords: [VocabChallengeWord]?,
        preferences: VocabChallengePreferences,
        now: Date = Date(),
        store: VocabChallengeStore = .standard,
        calendar: Calendar = .current
    ) -> DailyVocabChallenge? {
        guard preferences.isEnabled else { return nil }
        if let snapshotDayStamp, let snapshotWords {
            return challenge(dayStamp: snapshotDayStamp, words: snapshotWords)
        }
        guard dayStamp(recordedOn, calendar: calendar) == dayStamp(now, calendar: calendar) else {
            return nil
        }
        return todaysChallenge(preferences: preferences, now: now, store: store, calendar: calendar)
    }

    // MARK: - Picking

    /// Anki's leech rule, loosely: four missed days running means the word is
    /// being ignored, not learned.
    private static let leechThreshold = 4

    private static func emptyChallenge(dayStamp: String) -> DailyVocabChallenge {
        DailyVocabChallenge(dayStamp: dayStamp, words: [], usedKeys: [], isCompleted: false)
    }

    private static func fill(
        existing: [VocabChallengeWord],
        preferences: VocabChallengePreferences,
        usedCounts: [String: Int],
        skipped: Set<String>,
        seed: Int,
        reviews: [String: VocabReviewState],
        now: Date,
        generated: GeneratedVocabStore
    ) -> [VocabChallengeWord] {
        let target = preferences.resolvedWordCount
        var picked = existing
        var exclude = skipped
            .union(existing.map { $0.text.lowercased() })
            .union(bannedKeys(preferences))
        // Words spotlighted recently, scheduled or not. Only fresh picks
        // respect this — a due review is spaced repetition doing its job.
        let recent = recentlySpotlighted(reviews: reviews, now: now)

        let spaced = preferences.spacedReviewEnabled
        let ranked = rankedPool(
            preferences: preferences,
            usedCounts: usedCounts,
            seed: seed,
            reviews: reviews,
            now: now,
            generated: generated
        )

        func drain(_ pool: [VocabChallengeWord]) {
            for candidate in pool {
                if picked.count >= target { break }
                let key = candidate.text.lowercased()
                if exclude.contains(key) { continue }
                picked.append(candidate)
                exclude.insert(key)
            }
        }

        // One slot is held for a fresh word whenever there is more than one to
        // give, so a backlog of due reviews can never starve out learning. At a
        // single word a day there is nothing to reserve, and a word going stale
        // outranks meeting a new one.
        let reserveIntro = preferences.introduceNew && (!spaced || target >= 2)
        // Anything with a schedule is off the table for the random draw: it has
        // either just led the day or is deliberately resting, and re-teaching it
        // as brand new would reset the very schedule that is doing the work.
        let scheduled: Set<String> = spaced ? Set(reviews.keys) : []
        let introAlready = picked.contains { $0.source == .introduced }
        if reserveIntro, !introAlready, picked.count < target {
            if let intro = pickIntroduced(
                preferences: preferences,
                exclude: exclude.union(scheduled).union(recent),
                seed: seed,
                generated: generated
            ) {
                picked.append(intro)
                exclude.insert(intro.text.lowercased())
            }
        }

        drain(ranked.primary)

        if picked.count < target, preferences.introduceNew {
            let extras = pickIntroducedMany(
                preferences: preferences,
                exclude: exclude.union(scheduled).union(recent),
                seed: seed &+ 17,
                count: target - picked.count,
                generated: generated
            )
            picked.append(contentsOf: extras)
            exclude.formUnion(extras.map { $0.text.lowercased() })
        }

        // Words scheduled for later, used only to keep the card from going
        // empty on a day with nothing due and no new words left.
        drain(ranked.deferred)

        if picked.count > target {
            picked = Array(picked.prefix(target))
        }
        return picked
    }

    /// Grades every word from a previous day's pick that was never spoken.
    /// Missing it is the "again" review — FSRS pulls it back in tomorrow.
    private static func settleUnusedWords(
        before today: String,
        now: Date,
        store: VocabChallengeStore,
        calendar: Calendar
    ) {
        guard let cached = store.cached(), cached.dayStamp != today else { return }
        // Graded on the day it was missed, not today — otherwise a word skipped
        // on Monday would not resurface until the day after the user next opens
        // the app, and a week away would cost only one lapse-day.
        let missedOn = date(fromDayStamp: cached.dayStamp, calendar: calendar) ?? now
        var reviews = store.reviews()
        var changed = false
        for word in cached.words {
            let key = word.text.lowercased()
            if reviews[key]?.lastGradedDay == cached.dayStamp { continue }
            reviews[key] = VocabScheduler.review(reviews[key], grade: .again, on: missedOn, calendar: calendar)
            changed = true
        }
        if changed { store.saveReviews(reviews) }
    }

    /// Records that tracked words were actually spoken, which is the passing
    /// review. Idempotent per day, so re-analysing or a second session the same
    /// day does not double-count.
    static func recordUsage(
        _ usages: [VocabWordUsage],
        preferences: VocabChallengePreferences,
        now: Date = Date(),
        store: VocabChallengeStore = .standard,
        calendar: Calendar = .current
    ) {
        guard preferences.isEnabled, preferences.spacedReviewEnabled else { return }
        let stamp = dayStamp(now, calendar: calendar)
        var reviews = store.reviews()
        var changed = false
        for usage in usages where usage.count > 0 {
            let key = usage.word.lowercased()
            if reviews[key]?.lastGradedDay == stamp { continue }
            // Leaning on a word several times in one day is the strongest
            // signal available without asking the user to rate anything.
            let grade: VocabGrade = usage.count >= 3 ? .easy : .good
            reviews[key] = VocabScheduler.review(reviews[key], grade: grade, on: now, calendar: calendar)
            changed = true
        }
        if changed { store.saveReviews(reviews) }
    }

    private static func bannedKeys(_ preferences: VocabChallengePreferences) -> Set<String> {
        var keys = Set(preferences.extraBanned.map { $0.lowercased() })
        let nameParts = preferences.userName.split { !$0.isLetter }.map { $0.lowercased() }
        keys.formUnion(nameParts)
        return keys
    }

    /// How long a freshly shown word stays off the fresh-draw list. FSRS owns
    /// deliberate returns; this only stops chance from re-dealing a card the
    /// user just saw.
    private static let freshnessWindowDays = 21

    /// Keys graded inside the freshness window. Day stamps sort as strings, so
    /// a lexicographic cutoff is exact.
    private static func recentlySpotlighted(
        reviews: [String: VocabReviewState],
        now: Date,
        calendar: Calendar = .current
    ) -> Set<String> {
        guard let cutoff = calendar.date(byAdding: .day, value: -freshnessWindowDays, to: now) else {
            return []
        }
        let cutoffStamp = dayStamp(cutoff, calendar: calendar)
        return Set(
            reviews.compactMap { key, state in
                state.lastGradedDay >= cutoffStamp ? key : nil
            }
        )
    }

    /// The workout's full word book: the curated lexicon plus everything the
    /// on-device model has added since.
    private static func lexiconEntry(
        for key: String,
        generated: GeneratedVocabStore
    ) -> VocabLexiconEntry? {
        DefaultVocabLexicon.entry(for: key) ?? generated.entry(for: key)
    }

    /// `primary` is what today should draw from; `deferred` is everything FSRS
    /// wants to leave alone for now, kept only as a fallback.
    private static func rankedPool(
        preferences: VocabChallengePreferences,
        usedCounts: [String: Int],
        seed: Int,
        reviews: [String: VocabReviewState],
        now: Date,
        generated: GeneratedVocabStore
    ) -> (primary: [VocabChallengeWord], deferred: [VocabChallengeWord]) {
        var pool: [VocabChallengeWord] = []
        if preferences.useBank {
            for word in preferences.vocabWords {
                guard let candidate = makeCandidate(word, source: .bank, preferences: preferences, generated: generated) else { continue }
                pool.append(candidate)
            }
        }
        if preferences.useDictionary {
            let bankKeys = Set(preferences.vocabWords.map { $0.lowercased() })
            for word in preferences.dictionaryWords {
                if bankKeys.contains(word.lowercased()) { continue }
                guard let candidate = makeCandidate(word, source: .dictionary, preferences: preferences, generated: generated) else { continue }
                pool.append(candidate)
            }
        }

        // A word the workout taught is scheduled too, even when the user never
        // tapped Add. Without this a new word is spotlighted once and only ever
        // returns by chance, which is the opposite of what spacing is for.
        // Generated words get schedules on the same terms — they are first-class.
        if preferences.spacedReviewEnabled, preferences.introduceNew {
            var known = Set(pool.map(\.id))
            for (key, state) in reviews where state.due <= now && !known.contains(key) {
                guard let entry = lexiconEntry(for: key, generated: generated),
                      WordSafety.allowsForChallenge(entry.word),
                      !WordSafety.isUserName(entry.word, userName: preferences.userName) else { continue }
                pool.append(
                    VocabChallengeWord(
                        text: entry.word,
                        source: .introduced,
                        gloss: entry.gloss,
                        prompt: entry.prompt
                    )
                )
                known.insert(key)
            }
        }

        guard preferences.spacedReviewEnabled else {
            let unused = pool.filter { (usedCounts[$0.id] ?? 0) == 0 }
            let used = pool.filter { (usedCounts[$0.id] ?? 0) > 0 }
                .sorted { lhs, rhs in
                    let c0 = usedCounts[lhs.id] ?? 0
                    let c1 = usedCounts[rhs.id] ?? 0
                    if c0 != c1 { return c0 < c1 }
                    return stableHash(seed, lhs.text) < stableHash(seed, rhs.text)
                }
            return (shuffle(unused, seed: seed) + used, [])
        }

        // Most overdue first: the word closest to being forgotten is the one
        // worth spending a slot on. A word missed several days running has
        // stopped being a review and started being a nag, so it gives up the
        // lead — otherwise ignoring the workout pins the same words on screen
        // forever.
        func leads(_ word: VocabChallengeWord) -> Bool {
            guard let state = reviews[word.id] else { return false }
            return state.due <= now && (state.consecutiveLapses ?? 0) < leechThreshold
        }

        let due = pool
            .filter(leads)
            .sorted { (reviews[$0.id]?.due ?? now) < (reviews[$1.id]?.due ?? now) }
            .map { word -> VocabChallengeWord in
                var marked = word
                marked.isReview = true
                return marked
            }
        let fresh = pool.filter { reviews[$0.id] == nil }
        let rested = pool
            .filter { reviews[$0.id] != nil && !leads($0) }
            .sorted { (reviews[$0.id]?.due ?? now) < (reviews[$1.id]?.due ?? now) }

        return (due + shuffle(fresh, seed: seed), rested)
    }

    private static func makeCandidate(
        _ word: String,
        source: VocabChallengeWord.Source,
        preferences: VocabChallengePreferences,
        generated: GeneratedVocabStore
    ) -> VocabChallengeWord? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordSafety.allowsForChallenge(trimmed) else { return nil }
        if WordSafety.isUserName(trimmed, userName: preferences.userName) { return nil }
        let entry = lexiconEntry(for: trimmed.lowercased(), generated: generated)
        return VocabChallengeWord(
            text: trimmed,
            source: source,
            gloss: entry?.gloss,
            prompt: entry?.prompt ?? defaultPrompt(for: source)
        )
    }

    private static func defaultPrompt(for source: VocabChallengeWord.Source) -> String {
        switch source {
        case .bank: return "Use this in a sentence today."
        case .dictionary: return "Slip this term in naturally."
        case .introduced: return "Try this word in a sentence today."
        }
    }

    private static func pickIntroduced(
        preferences: VocabChallengePreferences,
        exclude: Set<String>,
        seed: Int,
        generated: GeneratedVocabStore
    ) -> VocabChallengeWord? {
        pickIntroducedMany(
            preferences: preferences,
            exclude: exclude,
            seed: seed,
            count: 1,
            generated: generated
        ).first
    }

    private static func pickIntroducedMany(
        preferences: VocabChallengePreferences,
        exclude: Set<String>,
        seed: Int,
        count: Int,
        generated: GeneratedVocabStore
    ) -> [VocabChallengeWord] {
        guard count > 0 else { return [] }
        let owned = Set(preferences.vocabWords.map { $0.lowercased() })
            .union(preferences.dictionaryWords.map { $0.lowercased() })
            .union(exclude)

        let level = preferences.resolvedIntroLevel
        // Curated words first so a generated duplicate of a curated one loses;
        // per-key dedupe keeps the shuffled prefix from holding the same word
        // twice.
        var seenKeys: Set<String> = []
        let all = (DefaultVocabLexicon.entries + generated.entries()).filter { entry in
            let key = entry.word.lowercased()
            guard !seenKeys.contains(key) else { return false }
            seenKeys.insert(key)
            return !owned.contains(key) && WordSafety.allowsForChallenge(entry.word)
        }
        let preferred = all.filter { $0.level == level }
        let adjacent = all.filter { abs($0.level - level) == 1 }
        let pool: [VocabLexiconEntry]
        if !preferred.isEmpty {
            pool = preferred
        } else if !adjacent.isEmpty {
            pool = adjacent
        } else {
            pool = all
        }

        let shuffled = shuffle(pool, seed: seed)
        return shuffled.prefix(count).map { entry in
            VocabChallengeWord(
                text: entry.word,
                source: .introduced,
                gloss: entry.gloss,
                prompt: entry.prompt
            )
        }
    }

    private static func shuffle<T>(_ items: [T], seed: Int) -> [T] {
        guard items.count > 1 else { return items }
        var result = items
        var state = UInt64(bitPattern: Int64(seed))
        if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
        for i in stride(from: result.count - 1, through: 1, by: -1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let j = Int(state % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }

    private static func stableHash(_ seed: Int, _ word: String) -> Int {
        var state = UInt64(bitPattern: Int64(seed))
        if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
        for byte in word.lowercased().utf8 {
            state = state &* 6_364_136_223_846_793_005 &+ UInt64(byte)
        }
        return Int(truncatingIfNeeded: state)
    }
}

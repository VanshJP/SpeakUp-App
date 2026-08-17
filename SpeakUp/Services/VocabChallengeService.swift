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
        usedCounts: [String: Int] = [:]
    ) -> [String] {
        todaysChallenge(
            preferences: preferences,
            usedCounts: usedCounts,
            now: now,
            store: store
        )?.words.map(\.text) ?? []
    }

    static func todaysChallenge(
        preferences: VocabChallengePreferences,
        usedCounts: [String: Int] = [:],
        now: Date = Date(),
        store: VocabChallengeStore = .standard,
        calendar: Calendar = .current
    ) -> DailyVocabChallenge? {
        guard preferences.isEnabled else { return nil }

        let stamp = dayStamp(now, calendar: calendar)
        let fingerprint = preferences.fingerprint
        let skipped = store.skipped(on: stamp)
        let seed = daySeed(now, calendar: calendar)

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
                seed: seed
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
            seed: seed
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
        store.skip(word, on: stamp)
        if var cached = store.cached(), cached.dayStamp == stamp {
            cached.words.removeAll { $0.text.caseInsensitiveCompare(word) == .orderedSame }
            store.save(cached)
        }
        return todaysChallenge(
            preferences: preferences,
            usedCounts: usedCounts,
            now: now,
            store: store,
            calendar: calendar
        )
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

    // MARK: - Picking

    private static func emptyChallenge(dayStamp: String) -> DailyVocabChallenge {
        DailyVocabChallenge(dayStamp: dayStamp, words: [], usedKeys: [], isCompleted: false)
    }

    private static func fill(
        existing: [VocabChallengeWord],
        preferences: VocabChallengePreferences,
        usedCounts: [String: Int],
        skipped: Set<String>,
        seed: Int
    ) -> [VocabChallengeWord] {
        let target = preferences.resolvedWordCount
        var picked = existing
        var exclude = skipped
            .union(existing.map { $0.text.lowercased() })
            .union(bannedKeys(preferences))

        let pool = rankedPool(
            preferences: preferences,
            usedCounts: usedCounts,
            seed: seed
        )

        let wantsIntro = preferences.introduceNew
        let introAlready = picked.contains { $0.source == .introduced }
        if wantsIntro, !introAlready, picked.count < target {
            if let intro = pickIntroduced(preferences: preferences, exclude: exclude, seed: seed) {
                picked.append(intro)
                exclude.insert(intro.text.lowercased())
            }
        }

        for candidate in pool {
            if picked.count >= target { break }
            let key = candidate.text.lowercased()
            if exclude.contains(key) { continue }
            picked.append(candidate)
            exclude.insert(key)
        }

        if picked.count < target, preferences.introduceNew {
            let extras = pickIntroducedMany(
                preferences: preferences,
                exclude: exclude,
                seed: seed &+ 17,
                count: target - picked.count
            )
            picked.append(contentsOf: extras)
        }

        if picked.count > target {
            picked = Array(picked.prefix(target))
        }
        return picked
    }

    private static func bannedKeys(_ preferences: VocabChallengePreferences) -> Set<String> {
        var keys = Set(preferences.extraBanned.map { $0.lowercased() })
        let nameParts = preferences.userName.split { !$0.isLetter }.map { $0.lowercased() }
        keys.formUnion(nameParts)
        return keys
    }

    private static func rankedPool(
        preferences: VocabChallengePreferences,
        usedCounts: [String: Int],
        seed: Int
    ) -> [VocabChallengeWord] {
        var pool: [VocabChallengeWord] = []
        if preferences.useBank {
            for word in preferences.vocabWords {
                guard let candidate = makeCandidate(word, source: .bank, preferences: preferences) else { continue }
                pool.append(candidate)
            }
        }
        if preferences.useDictionary {
            let bankKeys = Set(preferences.vocabWords.map { $0.lowercased() })
            for word in preferences.dictionaryWords {
                if bankKeys.contains(word.lowercased()) { continue }
                guard let candidate = makeCandidate(word, source: .dictionary, preferences: preferences) else { continue }
                pool.append(candidate)
            }
        }

        let unused = pool.filter { (usedCounts[$0.text.lowercased()] ?? 0) == 0 }
        let used = pool.filter { (usedCounts[$0.text.lowercased()] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let c0 = usedCounts[lhs.text.lowercased()] ?? 0
                let c1 = usedCounts[rhs.text.lowercased()] ?? 0
                if c0 != c1 { return c0 < c1 }
                return stableHash(seed, lhs.text) < stableHash(seed, rhs.text)
            }

        return shuffle(unused, seed: seed) + used
    }

    private static func makeCandidate(
        _ word: String,
        source: VocabChallengeWord.Source,
        preferences: VocabChallengePreferences
    ) -> VocabChallengeWord? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordSafety.allowsForChallenge(trimmed) else { return nil }
        if WordSafety.isUserName(trimmed, userName: preferences.userName) { return nil }
        let entry = DefaultVocabLexicon.entry(for: trimmed)
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
        seed: Int
    ) -> VocabChallengeWord? {
        pickIntroducedMany(preferences: preferences, exclude: exclude, seed: seed, count: 1).first
    }

    private static func pickIntroducedMany(
        preferences: VocabChallengePreferences,
        exclude: Set<String>,
        seed: Int,
        count: Int
    ) -> [VocabChallengeWord] {
        guard count > 0 else { return [] }
        let owned = Set(preferences.vocabWords.map { $0.lowercased() })
            .union(preferences.dictionaryWords.map { $0.lowercased() })
            .union(exclude)

        let level = min(2, max(0, preferences.speakerLevelRaw))
        let all = DefaultVocabLexicon.entries.filter { entry in
            let key = entry.word.lowercased()
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

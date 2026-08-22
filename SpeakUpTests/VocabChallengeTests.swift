import Testing
import Foundation
@testable import SpeakUp

struct WordSafetyTests {
    @Test func allowsOrdinarySpeakingWords() {
        #expect(WordSafety.allows("Articulate"))
        #expect(WordSafety.allows("Kubernetes"))
        #expect(WordSafety.allows("class"))
        #expect(WordSafety.allows("assessment"))
        #expect(WordSafety.allowsForChallenge("Strategic"))
    }

    @Test func blocksProfanityAndSlurs() {
        #expect(WordSafety.isBlocked("fuck"))
        #expect(WordSafety.isBlocked("shit"))
        #expect(WordSafety.rejection(for: "asshole") == .blocked)
        #expect(!WordSafety.allows("nigger"))
    }

    @Test func doesNotSubstringMatch() {
        #expect(WordSafety.allows("class"))
        #expect(WordSafety.allows("assessment"))
        #expect(WordSafety.allows("title"))
        #expect(WordSafety.allows("cocktail"))
    }

    @Test func fillersAreNotSpotlighted() {
        #expect(!WordSafety.allowsForChallenge("like"))
        #expect(!WordSafety.allowsForChallenge("basically"))
        #expect(!WordSafety.allowsForChallenge("um"))
        #expect(WordSafety.allows("like"))
    }

    @Test func shortWordsRejected() {
        #expect(WordSafety.rejection(for: "a") == .tooShort)
        #expect(!WordSafety.allowsForChallenge("OK"))
        #expect(WordSafety.rejection(for: "  ") == .empty)
    }

    @Test func userNameTokensAreDetectable() {
        #expect(WordSafety.isUserName("Ada", userName: "Ada Lovelace"))
        #expect(!WordSafety.isUserName("Strategic", userName: "Ada Lovelace"))
    }
}

struct VocabMatcherTests {
    @Test func detectsExactAndInflectedForms() {
        let text = "I want to sound more articulating and more resilient."
        let usages = VocabMatcher.usages(in: text, vocabWords: ["Articulate", "Resilient"])
        #expect(usages.contains { $0.word == "Articulate" && $0.count >= 1 })
        #expect(usages.contains { $0.word == "Resilient" && $0.count >= 1 })
    }

    @Test func mergeUniqueKeepsFirstCasing() {
        let merged = VocabMatcher.mergeUnique(["Focus", "Listen"], ["focus", "Engage"])
        #expect(merged == ["Focus", "Listen", "Engage"])
    }
}

struct VocabLexiconTests {
    @Test func everyEntryIsSafeAndUnique() {
        var seen: Set<String> = []
        for entry in DefaultVocabLexicon.entries {
            #expect(WordSafety.allowsForChallenge(entry.word), "Unsafe lexicon word: \(entry.word)")
            #expect(!entry.gloss.isEmpty)
            #expect(!entry.prompt.isEmpty)
            let key = entry.word.lowercased()
            #expect(!seen.contains(key), "Duplicate lexicon word: \(entry.word)")
            seen.insert(key)
        }
        #expect(DefaultVocabLexicon.entries.count >= 60)
    }

    @Test func lookupIsCaseInsensitive() {
        #expect(DefaultVocabLexicon.entry(for: "articulate")?.word == "Articulate")
    }
}

struct VocabChallengeServiceTests {
    private func makeStore() -> VocabChallengeStore {
        let suite = "VocabChallengeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return VocabChallengeStore(defaults: defaults)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func prefs(
        enabled: Bool = true,
        count: Int = 2,
        useBank: Bool = true,
        useDictionary: Bool = true,
        introduceNew: Bool = true,
        spaced: Bool = true,
        bank: [String] = ["Strategic", "Authentic"],
        dictionary: [String] = ["Kubernetes"],
        extraBanned: [String] = [],
        userName: String = "Ada",
        level: Int = 1
    ) -> VocabChallengePreferences {
        VocabChallengePreferences(
            isEnabled: enabled,
            wordCount: count,
            useBank: useBank,
            useDictionary: useDictionary,
            introduceNew: introduceNew,
            spacedReviewEnabled: spaced,
            vocabWords: bank,
            dictionaryWords: dictionary,
            extraBanned: extraBanned,
            userName: userName,
            speakerLevelRaw: level
        )
    }

    @Test func disabledReturnsNil() {
        let store = makeStore()
        let result = VocabChallengeService.todaysChallenge(
            preferences: prefs(enabled: false),
            now: day(2026, 8, 17),
            store: store
        )
        #expect(result == nil)
    }

    @Test func sameDayIsStable() {
        let store = makeStore()
        let now = day(2026, 8, 17)
        let first = VocabChallengeService.todaysChallenge(
            preferences: prefs(),
            now: now,
            store: store
        )
        let second = VocabChallengeService.todaysChallenge(
            preferences: prefs(),
            now: now,
            store: store
        )
        #expect(first?.words.map(\.text) == second?.words.map(\.text))
        #expect(first?.words.count == 2)
    }

    @Test func neverSpotlightsBlockedOrFillerOrName() {
        let store = makeStore()
        let result = VocabChallengeService.todaysChallenge(
            preferences: prefs(
                count: 3,
                useBank: true,
                useDictionary: true,
                introduceNew: false,
                bank: ["fuck", "like", "Ada", "Resilient", "um"],
                dictionary: ["shit", "Authentic"],
                userName: "Ada"
            ),
            now: day(2026, 8, 17),
            store: store
        )
        let texts = result?.words.map { $0.text.lowercased() } ?? []
        #expect(!texts.contains("fuck"))
        #expect(!texts.contains("like"))
        #expect(!texts.contains("ada"))
        #expect(!texts.contains("shit"))
        #expect(!texts.contains("um"))
        #expect(texts.contains("resilient") || texts.contains("authentic"))
    }

    @Test func emptyBankStillIntroducesNewWords() {
        let store = makeStore()
        let result = VocabChallengeService.todaysChallenge(
            preferences: prefs(
                count: 2,
                useBank: true,
                useDictionary: false,
                introduceNew: true,
                bank: [],
                dictionary: []
            ),
            now: day(2026, 8, 17),
            store: store
        )
        #expect(result?.words.count == 2)
        #expect(result?.words.allSatisfy { $0.source == .introduced } == true)
        #expect(result?.words.allSatisfy { WordSafety.allowsForChallenge($0.text) } == true)
    }

    @Test func skipReplacesTheWord() {
        let store = makeStore()
        let now = day(2026, 8, 17)
        let original = VocabChallengeService.todaysChallenge(
            preferences: prefs(count: 2, introduceNew: true),
            now: now,
            store: store
        )
        let skipped = original!.words[0].text
        let next = VocabChallengeService.skip(
            skipped,
            preferences: prefs(count: 2, introduceNew: true),
            now: now,
            store: store
        )
        let nextTexts = next?.words.map { $0.text.lowercased() } ?? []
        #expect(!nextTexts.contains(skipped.lowercased()))
        #expect(next?.words.count == 2)
    }

    @Test func skipKeepsTheReplacementInTheSkippedSlot() {
        let store = makeStore()
        let now = day(2026, 8, 17)
        let original = VocabChallengeService.todaysChallenge(
            preferences: prefs(count: 3),
            now: now,
            store: store
        )!
        #expect(original.words.count == 3)

        let skipped = original.words[0].text
        let next = VocabChallengeService.skip(
            skipped,
            preferences: prefs(count: 3),
            now: now,
            store: store
        )!

        // The rows the user did not touch must not move.
        #expect(next.words[1].text == original.words[1].text)
        #expect(next.words[2].text == original.words[2].text)
        #expect(next.words[0].text.caseInsensitiveCompare(skipped) != .orderedSame)
        // The order has to survive the round trip, since Today rebuilds from cache.
        #expect(store.cached()?.words.map(\.text) == next.words.map(\.text))
    }

    @Test func evaluateDetectsUsedWordsInTranscript() {
        let challenge = DailyVocabChallenge(
            dayStamp: "2026-08-17",
            words: [
                VocabChallengeWord(text: "Strategic", source: .bank, gloss: nil, prompt: ""),
                VocabChallengeWord(text: "Authentic", source: .bank, gloss: nil, prompt: "")
            ],
            usedKeys: [],
            isCompleted: false
        )
        let result = VocabChallengeService.evaluate(
            challenge,
            transcripts: ["I took a strategic pause and tried to stay authentic."],
            usages: []
        )
        #expect(result.used.map { $0.lowercased() }.sorted() == ["authentic", "strategic"])
        #expect(result.missed.isEmpty)
        #expect(result.isComplete)
    }

    @Test func evaluateRespectsUsageArray() {
        let challenge = DailyVocabChallenge(
            dayStamp: "2026-08-17",
            words: [
                VocabChallengeWord(text: "Resilient", source: .introduced, gloss: nil, prompt: "")
            ],
            usedKeys: [],
            isCompleted: false
        )
        let result = VocabChallengeService.evaluate(
            challenge,
            transcripts: [],
            usages: [VocabWordUsage(word: "Resilient", count: 2)]
        )
        #expect(result.isComplete)
    }

    @Test func dictionaryOnlyPool() {
        let store = makeStore()
        let result = VocabChallengeService.todaysChallenge(
            preferences: prefs(
                count: 1,
                useBank: false,
                useDictionary: true,
                introduceNew: false,
                bank: ["Strategic"],
                dictionary: ["Kubernetes"]
            ),
            now: day(2026, 8, 17),
            store: store
        )
        #expect(result?.words.map(\.text) == ["Kubernetes"])
        #expect(result?.words.first?.source == .dictionary)
    }
}

struct VocabSnapshotResolverTests {
    private func makeStore() -> VocabChallengeStore {
        let suite = "VocabSnapshotResolverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return VocabChallengeStore(defaults: defaults)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func prefs(enabled: Bool = true) -> VocabChallengePreferences {
        VocabChallengePreferences(
            isEnabled: enabled,
            wordCount: 2,
            useBank: true,
            useDictionary: false,
            introduceNew: true,
            spacedReviewEnabled: true,
            vocabWords: ["Strategic", "Authentic"],
            dictionaryWords: [],
            extraBanned: [],
            userName: "Ada",
            speakerLevelRaw: 1
        )
    }

    private func words(_ texts: String...) -> [VocabChallengeWord] {
        texts.map { VocabChallengeWord(text: $0, source: .bank, gloss: nil, prompt: "") }
    }

    @Test func resolverPicksSnapshotOverTodaysChallenge() {
        let store = makeStore()
        let monday = day(2026, 8, 17)
        let friday = day(2026, 8, 21)
        // A real pick from Monday so the stamp comes from the store's own path.
        _ = VocabChallengeService.todaysChallenge(preferences: prefs(), now: monday, store: store)
        let snapshotStamp = store.cached()?.dayStamp

        let resolved = VocabChallengeService.workout(
            forRecordingAt: friday,
            snapshotDayStamp: snapshotStamp,
            snapshotWords: words("Strategic"),
            preferences: prefs(),
            now: friday,
            store: store
        )

        #expect(resolved?.dayStamp == "2026-08-17")
        #expect(resolved?.words.map(\.text) == ["Strategic"])
    }

    @Test func todayFallbackFiresOnlyForTodaysRecording() {
        let store = makeStore()
        let today = day(2026, 8, 21)
        let direct = VocabChallengeService.todaysChallenge(
            preferences: prefs(),
            now: today,
            store: store
        )
        let freshStore = makeStore()
        let fallback = VocabChallengeService.workout(
            forRecordingAt: today,
            snapshotDayStamp: nil,
            snapshotWords: nil,
            preferences: prefs(),
            now: today,
            store: freshStore
        )
        #expect(fallback?.words.map(\.text) == direct?.words.map(\.text))

        let olderStore = makeStore()
        let older = VocabChallengeService.workout(
            forRecordingAt: day(2026, 8, 20),
            snapshotDayStamp: nil,
            snapshotWords: nil,
            preferences: prefs(),
            now: today,
            store: olderStore
        )
        #expect(older == nil)
    }

    @Test func legacyOlderRecordingHides() {
        let store = makeStore()
        let result = VocabChallengeService.workout(
            forRecordingAt: day(2025, 3, 2),
            snapshotDayStamp: nil,
            snapshotWords: nil,
            preferences: prefs(),
            now: day(2026, 8, 21),
            store: store
        )
        #expect(result == nil)
    }

    @Test func emptySnapshotHidesEvenOnItsOwnDay() {
        let store = makeStore()
        let result = VocabChallengeService.challenge(dayStamp: "2026-08-17", words: [])
        #expect(result == nil)

        let workout = VocabChallengeService.workout(
            forRecordingAt: day(2026, 8, 17),
            snapshotDayStamp: "2026-08-17",
            snapshotWords: [],
            preferences: prefs(),
            now: day(2026, 8, 17),
            store: store
        )
        #expect(workout == nil)
    }

    @Test func disabledWorkoutHidesEvenWithSnapshot() {
        let store = makeStore()
        let result = VocabChallengeService.workout(
            forRecordingAt: day(2026, 8, 21),
            snapshotDayStamp: "2026-08-17",
            snapshotWords: words("Strategic"),
            preferences: prefs(enabled: false),
            now: day(2026, 8, 21),
            store: store
        )
        #expect(result == nil)
    }

    @Test func dayStampRoundTripsThroughTheSameFormatterTheStoreUses() {
        let when = day(2026, 8, 17)
        let stamp = VocabChallengeService.dayStamp(when)
        #expect(VocabChallengeService.date(fromDayStamp: stamp) == when)

        let store = makeStore()
        _ = VocabChallengeService.todaysChallenge(preferences: prefs(), now: when, store: store)
        #expect(store.cached()?.dayStamp == stamp)

        let resolved = VocabChallengeService.workout(
            forRecordingAt: day(2026, 8, 18),
            snapshotDayStamp: stamp,
            snapshotWords: words("Strategic", "Authentic"),
            preferences: prefs(),
            now: day(2026, 8, 18),
            store: makeStore()
        )
        #expect(resolved?.dayStamp == stamp)
    }
}

struct VocabSchedulerTests {
    @Test func missedWordReturnsSoonerThanSpokenOne() {
        let now = Date()
        let spoken = VocabScheduler.review(nil, grade: .good, on: now)
        let missed = VocabScheduler.review(nil, grade: .again, on: now)
        #expect(missed.due < spoken.due)
        #expect(missed.lapses == 1)
        #expect(spoken.lapses == 0)
    }

    @Test func intervalGrowsAsAWordSticks() {
        let first = VocabScheduler.review(nil, grade: .good, on: Date())
        let second = VocabScheduler.review(first, grade: .good, on: first.due)
        #expect(second.due.timeIntervalSince(second.lastReview)
            > first.due.timeIntervalSince(first.lastReview))
        #expect(second.reps == 2)
    }

    @Test func forgettingNeverLooksLikeProgress() {
        let first = VocabScheduler.review(nil, grade: .good, on: Date())
        let second = VocabScheduler.review(first, grade: .good, on: first.due)
        let lapsed = VocabScheduler.review(second, grade: .again, on: second.due)
        #expect(lapsed.stability < second.stability)
        #expect(lapsed.due.timeIntervalSince(lapsed.lastReview)
            < second.due.timeIntervalSince(second.lastReview))
        #expect(lapsed.lapses == 1)
        #expect(lapsed.consecutiveLapses == 1)
    }

    @Test func intervalStaysUnderTheCeiling() {
        var state = VocabScheduler.review(nil, grade: .easy, on: Date())
        for _ in 0..<20 {
            state = VocabScheduler.review(state, grade: .easy, on: state.due)
        }
        let days = state.due.timeIntervalSince(state.lastReview) / 86_400
        #expect(days >= 1 && days <= 91)
    }
}

struct VocabSpacedReviewTests {
    private func makeStore() -> VocabChallengeStore {
        let suite = "VocabSpacedReviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return VocabChallengeStore(defaults: defaults)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func bankOnly(spaced: Bool = true) -> VocabChallengePreferences {
        VocabChallengePreferences(
            isEnabled: true,
            wordCount: 1,
            useBank: true,
            useDictionary: false,
            introduceNew: false,
            spacedReviewEnabled: spaced,
            vocabWords: ["Strategic", "Authentic"],
            dictionaryWords: [],
            extraBanned: [],
            userName: "Ada",
            speakerLevelRaw: 1
        )
    }

    @Test func aMissedWordComesBackTheNextDay() {
        let store = makeStore()
        let preferences = bankOnly()
        let monday = VocabChallengeService.todaysChallenge(
            preferences: preferences,
            now: day(2026, 8, 17),
            store: store
        )
        let missed = monday!.words[0].text

        let tuesday = VocabChallengeService.todaysChallenge(
            preferences: preferences,
            now: day(2026, 8, 18),
            store: store
        )
        #expect(tuesday?.words.map(\.text) == [missed])
        #expect(tuesday?.words.first?.isReview == true)
    }

    @Test func aSpokenWordRestsWhileAnotherGetsTheSlot() {
        let store = makeStore()
        let preferences = bankOnly()
        let monday = VocabChallengeService.todaysChallenge(
            preferences: preferences,
            now: day(2026, 8, 17),
            store: store
        )
        let spoken = monday!.words[0].text
        VocabChallengeService.recordUsage(
            [VocabWordUsage(word: spoken, count: 1)],
            preferences: preferences,
            now: day(2026, 8, 17),
            store: store
        )

        let tuesday = VocabChallengeService.todaysChallenge(
            preferences: preferences,
            now: day(2026, 8, 18),
            store: store
        )
        #expect(tuesday?.words.map(\.text) != [spoken])
        #expect(tuesday?.words.count == 1)
    }

    @Test func gradingIsIdempotentWithinADay() {
        let store = makeStore()
        let preferences = bankOnly()
        let monday = day(2026, 8, 17)
        let usage = [VocabWordUsage(word: "Strategic", count: 1)]
        VocabChallengeService.recordUsage(usage, preferences: preferences, now: monday, store: store)
        let afterFirst = store.reviews()["strategic"]
        VocabChallengeService.recordUsage(usage, preferences: preferences, now: monday, store: store)
        #expect(store.reviews()["strategic"] == afterFirst)
        #expect(afterFirst?.reps == 1)
    }

    @Test func spacingOffKeepsTheOldPickAndWritesNoSchedule() {
        let store = makeStore()
        let preferences = VocabChallengePreferences(
            isEnabled: true,
            wordCount: 2,
            useBank: true,
            useDictionary: false,
            introduceNew: true,
            spacedReviewEnabled: false,
            vocabWords: ["Strategic", "Authentic"],
            dictionaryWords: [],
            extraBanned: [],
            userName: "Ada",
            speakerLevelRaw: 1
        )
        let result = VocabChallengeService.todaysChallenge(
            preferences: preferences,
            now: day(2026, 8, 17),
            store: store
        )
        #expect(result?.words.first?.source == .introduced)
        #expect(result?.words.allSatisfy { $0.isReview != true } == true)

        VocabChallengeService.recordUsage(
            [VocabWordUsage(word: "Strategic", count: 2)],
            preferences: preferences,
            now: day(2026, 8, 17),
            store: store
        )
        #expect(store.reviews().isEmpty)
    }
}

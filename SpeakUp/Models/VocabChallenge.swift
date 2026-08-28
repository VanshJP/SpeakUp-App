import Foundation

/// Snapshot of word-workout knobs. Pure so picking can run off the main actor
/// and in tests without a SwiftData `UserSettings` row.
nonisolated struct VocabChallengePreferences: Sendable, Equatable {
    var isEnabled: Bool
    var wordCount: Int
    var useBank: Bool
    var useDictionary: Bool
    var introduceNew: Bool
    /// FSRS spacing. Off means the legacy pick: fresh words first, then the
    /// least-used ones.
    var spacedReviewEnabled: Bool = true
    var vocabWords: [String]
    var dictionaryWords: [String]
    var extraBanned: [String]
    var userName: String
    var speakerLevelRaw: Int
    /// Word-level control. 0 follows the speaker level; 1–3 force beginner,
    /// intermediate, or advanced regardless of it. Optional-style default so
    /// existing call sites and tests keep compiling.
    var levelOverrideRaw: Int = 0

    static let disabled = VocabChallengePreferences(
        isEnabled: false,
        wordCount: 2,
        useBank: true,
        useDictionary: true,
        introduceNew: true,
        spacedReviewEnabled: true,
        vocabWords: [],
        dictionaryWords: [],
        extraBanned: [],
        userName: "",
        speakerLevelRaw: 1
    )

    var resolvedWordCount: Int {
        min(3, max(1, wordCount))
    }

    /// The lexicon tier fresh picks draw from, after resolving the override.
    var resolvedIntroLevel: Int {
        if (1...3).contains(levelOverrideRaw) { return levelOverrideRaw - 1 }
        return min(2, max(0, speakerLevelRaw))
    }

    /// Whether the user pinned a tier instead of following the speaker level.
    var forcesIntroLevel: Bool {
        (1...3).contains(levelOverrideRaw)
    }

    /// Cache key for the day's pick. Word lists stay out so adding a bank word
    /// mid-day does not reshuffle the workout already on screen.
    var fingerprint: String {
        "\(isEnabled)|\(resolvedWordCount)|\(useBank)|\(useDictionary)|\(introduceNew)|\(spacedReviewEnabled)|\(resolvedIntroLevel)"
    }
}

nonisolated struct VocabChallengeWord: Sendable, Equatable, Identifiable, Codable {
    var text: String
    var source: Source
    var gloss: String?
    var prompt: String
    /// Set when FSRS brought the word back because it was due, not because it
    /// was new. Optional so day caches written before spacing still decode.
    var isReview: Bool?

    var id: String { text.lowercased() }

    enum Source: String, Codable, Sendable {
        case bank
        case dictionary
        case introduced
    }

    var coachLine: String {
        prompt.isEmpty ? "Use this in a sentence today." : prompt
    }
}

nonisolated struct DailyVocabChallenge: Sendable, Equatable {
    var dayStamp: String
    var words: [VocabChallengeWord]
    var usedKeys: Set<String>
    var isCompleted: Bool

    var usedCount: Int { usedKeys.count }

    func isUsed(_ word: VocabChallengeWord) -> Bool {
        usedKeys.contains(word.text.lowercased())
    }
}

nonisolated struct VocabChallengeEvaluation: Sendable, Equatable {
    var used: [String]
    var missed: [String]

    var isComplete: Bool {
        missed.isEmpty && !used.isEmpty
    }
}

import Foundation

/// Snapshot of word-workout knobs. Pure so picking can run off the main actor
/// and in tests without a SwiftData `UserSettings` row.
nonisolated struct VocabChallengePreferences: Sendable, Equatable {
    var isEnabled: Bool
    var wordCount: Int
    var useBank: Bool
    var useDictionary: Bool
    var introduceNew: Bool
    var spacedReviewEnabled: Bool = true
    var vocabWords: [String]
    var dictionaryWords: [String]
    var extraBanned: [String]
    var userName: String
    var speakerLevelRaw: Int
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

    var resolvedIntroLevel: Int {
        if (1...3).contains(levelOverrideRaw) { return levelOverrideRaw - 1 }
        return min(2, max(0, speakerLevelRaw))
    }

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

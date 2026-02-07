import Foundation
import SwiftUI

// MARK: - Transcription Types

struct TranscriptionWord: Codable, Identifiable {
    var id: UUID = UUID()
    let word: String
    let start: TimeInterval
    let end: TimeInterval
    var confidence: Double?
    var isFiller: Bool
    
    init(word: String, start: TimeInterval, end: TimeInterval, confidence: Double? = nil, isFiller: Bool = false) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
        self.isFiller = isFiller
    }
    
    var duration: TimeInterval {
        end - start
    }
}

struct FillerWord: Codable, Identifiable {
    var id: UUID = UUID()
    let word: String
    var count: Int
    var timestamps: [TimeInterval]
    
    init(word: String, count: Int = 0, timestamps: [TimeInterval] = []) {
        self.word = word
        self.count = count
        self.timestamps = timestamps
    }
}

// MARK: - Speech Analysis

struct SpeechAnalysis: Codable {
    var fillerWords: [FillerWord]
    var totalWords: Int
    var wordsPerMinute: Double
    var pauseCount: Int
    var averagePauseLength: TimeInterval
    var clarity: Double // 0-100
    var speechScore: SpeechScore
    
    init(
        fillerWords: [FillerWord] = [],
        totalWords: Int = 0,
        wordsPerMinute: Double = 0,
        pauseCount: Int = 0,
        averagePauseLength: TimeInterval = 0,
        clarity: Double = 0,
        speechScore: SpeechScore = SpeechScore()
    ) {
        self.fillerWords = fillerWords
        self.totalWords = totalWords
        self.wordsPerMinute = wordsPerMinute
        self.pauseCount = pauseCount
        self.averagePauseLength = averagePauseLength
        self.clarity = clarity
        self.speechScore = speechScore
    }
    
    var totalFillerCount: Int {
        fillerWords.reduce(0) { $0 + $1.count }
    }
    
    var fillerPercentage: Double {
        guard totalWords > 0 else { return 0 }
        return (Double(totalFillerCount) / Double(totalWords)) * 100
    }
}

// MARK: - Speech Score

struct SpeechScore: Codable {
    var overall: Int // 0-100
    var subscores: SpeechSubscores
    var trend: ScoreTrend
    
    init(
        overall: Int = 0,
        subscores: SpeechSubscores = SpeechSubscores(),
        trend: ScoreTrend = .stable
    ) {
        self.overall = overall
        self.subscores = subscores
        self.trend = trend
    }
}

struct SpeechSubscores: Codable {
    var clarity: Int      // 0-100: Based on filler word frequency
    var pace: Int         // 0-100: Based on WPM (optimal ~150)
    var fillerUsage: Int  // 0-100: Inverse of filler word ratio
    var pauseQuality: Int // 0-100: Natural vs awkward pauses
    
    init(
        clarity: Int = 0,
        pace: Int = 0,
        fillerUsage: Int = 0,
        pauseQuality: Int = 0
    ) {
        self.clarity = clarity
        self.pace = pace
        self.fillerUsage = fillerUsage
        self.pauseQuality = pauseQuality
    }
}

enum ScoreTrend: String, Codable {
    case improving
    case stable
    case declining
    
    var iconName: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }
    
    var color: Color {
        switch self {
        case .improving: return .green
        case .stable: return .gray
        case .declining: return .red
        }
    }
}

// MARK: - Filler Words List

struct FillerWordList {
    // Words that are ALWAYS fillers (hesitation sounds)
    // Includes variations that Whisper might transcribe
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

    // Words that require context to determine if they're fillers
    static let contextDependentFillers: Set<String> = [
        "like", "so", "just", "well", "right", "okay",
        "actually", "basically", "literally", "honestly", "seriously"
    ]

    // Multi-word filler phrases
    static let fillerPhrases: Set<String> = [
        "you know", "i mean", "sort of", "kind of"
    ]

    // Words that typically precede verbs (non-filler context for "like")
    private static let verbPreceders: Set<String> = [
        "would", "do", "does", "did", "don't", "doesn't", "didn't",
        "i", "you", "we", "they", "he", "she", "it",
        "really", "actually", "also", "always", "never"
    ]

    // Linking verbs that often precede quotative "like"
    private static let linkingVerbs: Set<String> = [
        "was", "is", "are", "were", "be", "been", "being",
        "felt", "looked", "seemed", "acted"
    ]

    // Common adjectives/adverbs that follow filler "like"
    private static let fillerFollowers: Set<String> = [
        "really", "totally", "super", "very", "so", "pretty",
        "kind", "sort", "completely", "absolutely", "honestly"
    ]

    /// Simple check - use for backward compatibility or when context isn't available
    static func isFillerWord(_ word: String) -> Bool {
        let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Unconditional fillers always match
        if unconditionalFillers.contains(lowercased) {
            return true
        }

        // Check for repeated characters (e.g., "ummmmm" -> "um")
        let collapsed = collapseRepeatedChars(lowercased)
        if unconditionalFillers.contains(collapsed) {
            return true
        }

        // Context-dependent words default to false without context
        return false
    }

    /// Context-aware filler detection - preferred method
    static func isFillerWord(
        _ word: String,
        previousWord: String?,
        nextWord: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool = false
    ) -> Bool {
        let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Unconditional fillers always match
        if unconditionalFillers.contains(w) || unconditionalFillers.contains(collapseRepeatedChars(w)) {
            return true
        }

        // Context-dependent words need analysis
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

    /// Check if two consecutive words form a filler phrase
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
            // Default: surrounded by pauses = likely filler
            return pauseBefore && pauseAfter
        }
    }

    /// Detect "like" as filler vs verb/preposition
    private static func isLikeFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial "Like, ..." is almost always filler
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Pattern 2: "was/is like" (quotative) - "She was like, 'no way'"
        if let p = prev, linkingVerbs.contains(p) {
            return true
        }

        // Pattern 3: Surrounded by pauses - "I was, like, confused"
        if pauseBefore && pauseAfter {
            return true
        }

        // Pattern 4: Before filler-typical words - "like totally", "like really"
        if let n = next, fillerFollowers.contains(n) {
            return true
        }

        // Anti-pattern 1: After modal/auxiliary - "would like", "do like"
        if let p = prev, verbPreceders.contains(p) {
            return false
        }

        // Anti-pattern 2: Comparative "like" - typically no pauses
        // "runs like the wind", "looks like rain"
        if !pauseBefore && !pauseAfter {
            return false
        }

        // Default: single pause suggests possible filler
        return pauseBefore || pauseAfter
    }

    /// Detect "so" as filler vs intensifier/conjunction
    private static func isSoFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial with pause - "So, anyway..."
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Anti-pattern 1: Intensifier - "so good", "so much", "not so"
        if let p = prev, p == "not" {
            return false
        }

        // Anti-pattern 2: Before adjective without pause (intensifier)
        if !pauseAfter && next != nil {
            return false
        }

        // Surrounded by pauses = filler
        return pauseBefore && pauseAfter
    }

    /// Detect "just" as filler vs adverb
    private static func isJustFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {
        // "just" as filler is typically pause-surrounded and adds no meaning
        // "I, just, don't know" vs "I just arrived" (timing)

        // Surrounded by pauses = likely filler
        if pauseBefore && pauseAfter {
            return true
        }

        // Without pauses, "just" is usually meaningful
        return false
    }

    /// Detect "well" as filler vs adverb
    private static func isWellFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Pattern 1: Sentence-initial "Well, ..." is typically filler
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Anti-pattern: "very well", "quite well", "as well"
        if let p = prev, ["very", "quite", "as", "pretty", "really"].contains(p) {
            return false
        }

        // Anti-pattern: "well done", "well made"
        if let n = next, ["done", "made", "known", "written", "said"].contains(n) {
            return false
        }

        return pauseBefore && pauseAfter
    }

    /// Detect "right"/"okay" as fillers (seeking confirmation vs adjective)
    private static func isRightOkayFiller(
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool
    ) -> Bool {
        // "right?" and "okay?" at end of sentences are confirmation-seeking fillers
        // "the right way" is not a filler

        // Anti-pattern: Article before = adjective ("the right answer")
        if let p = prev, ["the", "a", "an", "that", "this"].contains(p) {
            return false
        }

        // Surrounded by pauses or sentence-final = likely filler
        return pauseBefore || pauseAfter
    }

    /// Detect adverbs like "actually", "basically" as fillers
    private static func isAdverbFiller(
        word: String,
        prev: String?,
        next: String?,
        pauseBefore: Bool,
        pauseAfter: Bool,
        isStartOfSentence: Bool
    ) -> Bool {
        // Sentence-initial with pause = filler
        // "Actually, I think..." vs "I actually think..."
        if isStartOfSentence && pauseAfter {
            return true
        }

        // Mid-sentence surrounded by pauses = filler
        if pauseBefore && pauseAfter {
            return true
        }

        // Without pauses, these usually modify the following word meaningfully
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
}

// MARK: - User Statistics

struct UserStats {
    var totalRecordings: Int
    var totalPracticeTime: TimeInterval // in seconds
    var currentStreak: Int
    var longestStreak: Int
    var averageScore: Double
    var scoreHistory: [ScoreHistoryEntry]
    var mostUsedFillers: [FillerWord]
    var improvementRate: Double // percentage change over last 7 days
    
    init(
        totalRecordings: Int = 0,
        totalPracticeTime: TimeInterval = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        averageScore: Double = 0,
        scoreHistory: [ScoreHistoryEntry] = [],
        mostUsedFillers: [FillerWord] = [],
        improvementRate: Double = 0
    ) {
        self.totalRecordings = totalRecordings
        self.totalPracticeTime = totalPracticeTime
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.averageScore = averageScore
        self.scoreHistory = scoreHistory
        self.mostUsedFillers = mostUsedFillers
        self.improvementRate = improvementRate
    }
    
    var formattedPracticeTime: String {
        let hours = Int(totalPracticeTime) / 3600
        let minutes = (Int(totalPracticeTime) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct ScoreHistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    let date: Date
    let score: Int
}

// MARK: - Weekly Activity

struct WeeklyActivity: Identifiable {
    var id: Date { weekStart }
    let weekStart: Date
    var sessions: Int
    var totalMinutes: TimeInterval
    var averageScore: Double
    
    var formattedWeek: String {
        weekStart.formatted(.dateTime.month(.abbreviated).day())
    }
}

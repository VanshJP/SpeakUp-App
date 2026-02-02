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
    static let defaultFillers: Set<String> = [
        // Core hesitation sounds (with variations)
        "um", "umm", "ummm",
        "uh", "uhh", "uhhh",
        "er", "err",
        "ah", "ahh",
        "hmm", "hmmm",

        // Filler words
        "like", "just", "so", "well", "right", "okay", "yeah",
        "actually", "basically", "literally", "honestly", "seriously",

        // Filler phrases
        "you know", "i mean", "sort of", "kind of"
    ]

    static func isFillerWord(_ word: String) -> Bool {
        let lowercased = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Direct match
        if defaultFillers.contains(lowercased) {
            return true
        }

        // Check for repeated characters (e.g., "ummmmm" -> "um")
        let collapsed = collapseRepeatedChars(lowercased)
        return defaultFillers.contains(collapsed)
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

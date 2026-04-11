import Foundation

// MARK: - Session Feedback Types

nonisolated enum FeedbackQuestionType: String, Codable {
    case scale // 1-5
    case yesNo
}

nonisolated struct FeedbackQuestion: Codable, Identifiable {
    var id: UUID
    var text: String
    var type: FeedbackQuestionType

    init(id: UUID = UUID(), text: String, type: FeedbackQuestionType) {
        self.id = id
        self.text = text
        self.type = type
    }
}

nonisolated struct FeedbackAnswer: Codable, Identifiable {
    var id: UUID = UUID()
    var questionId: UUID
    var questionText: String
    var type: FeedbackQuestionType
    var scaleValue: Int?
    var boolValue: Bool?

    init(questionId: UUID, questionText: String, type: FeedbackQuestionType, scaleValue: Int? = nil, boolValue: Bool? = nil) {
        self.questionId = questionId
        self.questionText = questionText
        self.type = type
        self.scaleValue = scaleValue
        self.boolValue = boolValue
    }
}

nonisolated struct SessionFeedback: Codable {
    var answers: [FeedbackAnswer]
    var submittedAt: Date

    init(answers: [FeedbackAnswer], submittedAt: Date = Date()) {
        self.answers = answers
        self.submittedAt = submittedAt
    }
}

// MARK: - User Statistics

nonisolated struct UserStats: Sendable {
    var totalRecordings: Int
    var totalPracticeTime: TimeInterval // in seconds
    var currentStreak: Int
    var longestStreak: Int
    var averageScore: Double
    var scoreHistory: [ScoreHistoryEntry]
    var mostUsedFillers: [FillerWord]
    var improvementRate: Double // percentage change over last 7 days
    var weeklySessionCount: Int
    var weeklyGoalSessions: Int

    init(
        totalRecordings: Int = 0,
        totalPracticeTime: TimeInterval = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        averageScore: Double = 0,
        scoreHistory: [ScoreHistoryEntry] = [],
        mostUsedFillers: [FillerWord] = [],
        improvementRate: Double = 0,
        weeklySessionCount: Int = 0,
        weeklyGoalSessions: Int = 5
    ) {
        self.totalRecordings = totalRecordings
        self.totalPracticeTime = totalPracticeTime
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.averageScore = averageScore
        self.scoreHistory = scoreHistory
        self.mostUsedFillers = mostUsedFillers
        self.improvementRate = improvementRate
        self.weeklySessionCount = weeklySessionCount
        self.weeklyGoalSessions = weeklyGoalSessions
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

nonisolated struct ScoreHistoryEntry: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let date: Date
    let score: Int
}

// MARK: - Weekly Activity

nonisolated struct WeeklyActivity: Identifiable {
    var id: Date { weekStart }
    let weekStart: Date
    var sessions: Int
    var totalMinutes: TimeInterval
    var averageScore: Double

    var formattedWeek: String {
        weekStart.formatted(.dateTime.month(.abbreviated).day())
    }
}

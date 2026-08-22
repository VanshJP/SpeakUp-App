import Foundation

/// Shared data access via App Group for widgets.
/// Both the main app and widget extension read/write to the shared UserDefaults suite.
enum WidgetDataProvider {
    static let suiteName = "group.com.speakup.shared"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Write (from main app)

    static func updateStreak(_ streak: Int) {
        defaults.set(streak, forKey: "currentStreak")
    }

    static func updateTodaysPrompt(text: String, category: String, id: String) {
        defaults.set(text, forKey: "todaysPromptText")
        defaults.set(category, forKey: "todaysPromptCategory")
        defaults.set(id, forKey: "todaysPromptId")
    }

    static func updateLastScore(_ score: Int) {
        defaults.set(score, forKey: "lastScore")
    }

    static func updateWeeklyProgress(sessionCount: Int, goalSessions: Int, averageScore: Int, practiceMinutes: Int, improvementRate: Int = 0) {
        defaults.set(sessionCount, forKey: "weeklySessionCount")
        defaults.set(goalSessions, forKey: "weeklyGoalSessions")
        defaults.set(averageScore, forKey: "weeklyAverageScore")
        defaults.set(practiceMinutes, forKey: "weeklyPracticeMinutes")
        defaults.set(improvementRate, forKey: "weeklyImprovementRate")
    }


    static func updateLastPracticeDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: "lastPracticeDate")
    }

    static func updateInterviewReadiness(_ score: Int) {
        defaults.set(score, forKey: "interviewReadinessScore")
    }

    // MARK: - Story Data

    static func updateLatestStory(title: String, storyCount: Int) {
        defaults.set(title, forKey: "latestStoryTitle")
        defaults.set(storyCount, forKey: "storyCount")
    }
}

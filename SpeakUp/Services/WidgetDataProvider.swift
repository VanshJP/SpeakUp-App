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

    static func updateSkillMastery(clarity: Int, pace: Int, filler: Int, pause: Int) {
        defaults.set(clarity, forKey: "skillClarity")
        defaults.set(pace, forKey: "skillPace")
        defaults.set(filler, forKey: "skillFiller")
        defaults.set(pause, forKey: "skillPause")
    }

    static func updateDailyChallenge(title: String, description: String, icon: String, isCompleted: Bool) {
        defaults.set(title, forKey: "dailyChallengeTitle")
        defaults.set(description, forKey: "dailyChallengeDescription")
        defaults.set(icon, forKey: "dailyChallengeIcon")
        defaults.set(isCompleted, forKey: "dailyChallengeCompleted")
    }

    static func updateLastPracticeDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: "lastPracticeDate")
    }

    // MARK: - Story Data

    static func updateLatestStory(title: String) {
        defaults.set(title, forKey: "latestStoryTitle")
        defaults.set(defaults.integer(forKey: "storyCount") + 1, forKey: "storyCount")
    }
}

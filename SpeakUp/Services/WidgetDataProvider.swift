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

    // MARK: - Read (from widget)

    static var currentStreak: Int {
        defaults.integer(forKey: "currentStreak")
    }

    static var todaysPromptText: String {
        defaults.string(forKey: "todaysPromptText") ?? "Open the app to get your daily prompt"
    }

    static var todaysPromptCategory: String {
        defaults.string(forKey: "todaysPromptCategory") ?? ""
    }

    static var todaysPromptId: String {
        defaults.string(forKey: "todaysPromptId") ?? ""
    }

    static var lastScore: Int {
        defaults.integer(forKey: "lastScore")
    }

    static var weeklySessionCount: Int {
        defaults.integer(forKey: "weeklySessionCount")
    }

    static var weeklyGoalSessions: Int {
        let value = defaults.integer(forKey: "weeklyGoalSessions")
        return value == 0 ? 5 : value
    }

    static var weeklyAverageScore: Int {
        defaults.integer(forKey: "weeklyAverageScore")
    }

    static var weeklyPracticeMinutes: Int {
        defaults.integer(forKey: "weeklyPracticeMinutes")
    }

    static var dailyChallengeTitle: String {
        defaults.string(forKey: "dailyChallengeTitle") ?? "Open app for today's challenge"
    }

    static var dailyChallengeDescription: String {
        defaults.string(forKey: "dailyChallengeDescription") ?? ""
    }

    static var dailyChallengeIcon: String {
        defaults.string(forKey: "dailyChallengeIcon") ?? "target"
    }

    static var dailyChallengeCompleted: Bool {
        defaults.bool(forKey: "dailyChallengeCompleted")
    }

}

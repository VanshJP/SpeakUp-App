import Foundation

/// Shared data access via App Group for widgets.
/// Both the main app and widget extension read/write to the shared UserDefaults suite.
enum WidgetDataProvider {
    static let suiteName = "group.com.speakup.shared"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Write (from main app)

    static func updateStreak(_ streak: Int) {
        defaults?.set(streak, forKey: "currentStreak")
    }

    static func updateTodaysPrompt(text: String, category: String, id: String) {
        defaults?.set(text, forKey: "todaysPromptText")
        defaults?.set(category, forKey: "todaysPromptCategory")
        defaults?.set(id, forKey: "todaysPromptId")
    }

    static func updateLastScore(_ score: Int) {
        defaults?.set(score, forKey: "lastScore")
    }

    static func updateWeeklyProgress(sessionCount: Int, goalSessions: Int, averageScore: Int, practiceMinutes: Int) {
        defaults?.set(sessionCount, forKey: "weeklySessionCount")
        defaults?.set(goalSessions, forKey: "weeklyGoalSessions")
        defaults?.set(averageScore, forKey: "weeklyAverageScore")
        defaults?.set(practiceMinutes, forKey: "weeklyPracticeMinutes")
    }

    static func updateSkillMastery(clarity: Int, pace: Int, filler: Int, pause: Int) {
        defaults?.set(clarity, forKey: "skillClarity")
        defaults?.set(pace, forKey: "skillPace")
        defaults?.set(filler, forKey: "skillFiller")
        defaults?.set(pause, forKey: "skillPause")
    }

    static func updateDailyChallenge(title: String, description: String, icon: String, isCompleted: Bool) {
        defaults?.set(title, forKey: "dailyChallengeTitle")
        defaults?.set(description, forKey: "dailyChallengeDescription")
        defaults?.set(icon, forKey: "dailyChallengeIcon")
        defaults?.set(isCompleted, forKey: "dailyChallengeCompleted")
    }

    // MARK: - Read (from widget)

    static var currentStreak: Int {
        defaults?.integer(forKey: "currentStreak") ?? 0
    }

    static var todaysPromptText: String {
        defaults?.string(forKey: "todaysPromptText") ?? "Open the app to get your daily prompt"
    }

    static var todaysPromptCategory: String {
        defaults?.string(forKey: "todaysPromptCategory") ?? ""
    }

    static var todaysPromptId: String {
        defaults?.string(forKey: "todaysPromptId") ?? ""
    }

    static var lastScore: Int {
        defaults?.integer(forKey: "lastScore") ?? 0
    }

    static var weeklySessionCount: Int {
        defaults?.integer(forKey: "weeklySessionCount") ?? 0
    }

    static var weeklyGoalSessions: Int {
        defaults?.integer(forKey: "weeklyGoalSessions") ?? 5
    }

    static var weeklyAverageScore: Int {
        defaults?.integer(forKey: "weeklyAverageScore") ?? 0
    }

    static var weeklyPracticeMinutes: Int {
        defaults?.integer(forKey: "weeklyPracticeMinutes") ?? 0
    }

    static var weeklyImprovementRate: Int {
        defaults?.integer(forKey: "weeklyImprovementRate") ?? 0
    }

    static var skillClarity: Int {
        defaults?.integer(forKey: "skillClarity") ?? 0
    }

    static var skillPace: Int {
        defaults?.integer(forKey: "skillPace") ?? 0
    }

    static var skillFiller: Int {
        defaults?.integer(forKey: "skillFiller") ?? 0
    }

    static var skillPause: Int {
        defaults?.integer(forKey: "skillPause") ?? 0
    }

    static var dailyChallengeTitle: String {
        defaults?.string(forKey: "dailyChallengeTitle") ?? "Open app for today's challenge"
    }

    static var dailyChallengeDescription: String {
        defaults?.string(forKey: "dailyChallengeDescription") ?? ""
    }

    static var dailyChallengeIcon: String {
        defaults?.string(forKey: "dailyChallengeIcon") ?? "target"
    }

    static var dailyChallengeCompleted: Bool {
        defaults?.bool(forKey: "dailyChallengeCompleted") ?? false
    }

    // Story data
    static func updateLatestStory(title: String) {
        defaults?.set(title, forKey: "latestStoryTitle")
        defaults?.set(storyCount + 1, forKey: "storyCount")
    }

    static var latestStoryTitle: String {
        defaults?.string(forKey: "latestStoryTitle") ?? ""
    }

    static var storyCount: Int {
        defaults?.integer(forKey: "storyCount") ?? 0
    }

    // Streak tracking
    static var lastPracticeDate: Date? {
        guard let interval = defaults?.object(forKey: "lastPracticeDate") as? Double else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    static var hasPracticedToday: Bool {
        guard let lastDate = lastPracticeDate else { return false }
        return Calendar.current.isDateInToday(lastDate)
    }
}

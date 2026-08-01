import Foundation

/// Shared data access via App Group for widgets.
/// The main app writes; this extension only reads.
enum WidgetDataProvider {
    static let suiteName = "group.com.speakup.shared"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
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

import Foundation
import SwiftUI

/// Score ramp mirroring the app's `AppColors.scoreColor(for:)`. The widget
/// target cannot import app types, so the hex values are duplicated here —
/// keep in sync with AppColors (scoreHigh #38CC80, scoreGood #F5C542,
/// scoreMid #FF9036, scoreLow #F5544A).
func widgetScoreColor(for score: Int) -> Color {
    switch score {
    case 80...100: return Color(red: 56/255, green: 204/255, blue: 128/255)  // #38CC80
    case 60..<80: return Color(red: 245/255, green: 197/255, blue: 66/255)   // #F5C542
    case 40..<60: return Color(red: 255/255, green: 144/255, blue: 54/255)   // #FF9036
    default: return Color(red: 245/255, green: 84/255, blue: 74/255)         // #F5544A
    }
}

/// Shared data access via App Group for widgets.
/// The main app writes; this extension only reads.
enum WidgetDataProvider {
    static let suiteName = "group.com.speakup.shared"

    private static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        ) != nil else { return nil }
        return UserDefaults(suiteName: suiteName)
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

    static var latestStoryTitle: String {
        defaults?.string(forKey: "latestStoryTitle") ?? ""
    }

    static var storyCount: Int {
        defaults?.integer(forKey: "storyCount") ?? 0
    }

    /// Cross-session interview readiness written by TodayViewModel. `0` means
    /// no analyzed history yet — widgets treat it as "no data", not a real 0.
    static var interviewReadinessScore: Int {
        defaults?.integer(forKey: "interviewReadinessScore") ?? 0
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

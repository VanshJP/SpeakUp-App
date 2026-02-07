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
}

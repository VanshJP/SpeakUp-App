import CryptoKit
import Foundation

/// Shared data access via App Group for widgets.
/// Both the main app and widget extension read/write to the shared UserDefaults suite.
enum WidgetDataProvider {
    static let suiteName = "group.com.speakup.shared"

    private static let stateFingerprintKey = "widgetStateFingerprint"

    /// Nil outside a process that actually holds the App Group entitlement
    /// (Xcode Previews, unit-test hosts): touching the suite there is what
    /// makes cfprefsd log "kCFPreferencesAnyUser … detaching" and every write
    /// would be lost anyway. Never fall back to `.standard` — that domain is
    /// not shared with the widget.
    private static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        ) != nil else { return nil }
        return UserDefaults(suiteName: suiteName)
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

    static func updateWeeklyProgress(sessionCount: Int, goalSessions: Int, averageScore: Int, practiceMinutes: Int, improvementRate: Int = 0) {
        defaults?.set(sessionCount, forKey: "weeklySessionCount")
        defaults?.set(goalSessions, forKey: "weeklyGoalSessions")
        defaults?.set(averageScore, forKey: "weeklyAverageScore")
        defaults?.set(practiceMinutes, forKey: "weeklyPracticeMinutes")
        defaults?.set(improvementRate, forKey: "weeklyImprovementRate")
    }


    static func updateLastPracticeDate(_ date: Date) {
        defaults?.set(date.timeIntervalSince1970, forKey: "lastPracticeDate")
    }

    /// Removes the stored timestamp so widget readers fall back to their
    /// "no practice yet" default when Today's data has none (e.g. every
    /// recording was deleted).
    static func clearLastPracticeDate() {
        defaults?.removeObject(forKey: "lastPracticeDate")
    }

    static func updateInterviewReadiness(_ score: Int) {
        defaults?.set(score, forKey: "interviewReadinessScore")
    }

    // MARK: - Change gate

    /// True when any payload component differs from the previous call; stores
    /// the new fingerprint so callers can skip redundant App Group writes and
    /// timeline reloads (loadData runs on every Today appearance). First run
    /// has no stored fingerprint, so it always reports a change.
    static func todayPayloadChanged(_ components: [String]) -> Bool {
        // Length-prefix each component before joining so payload text that
        // contains the separator byte (U+001F can arrive via CSV prompt
        // import) cannot splice two components into one and mask a change.
        let joined = components.map { "\($0.count):\($0)" }.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        guard defaults?.string(forKey: stateFingerprintKey) != fingerprint else { return false }
        defaults?.set(fingerprint, forKey: stateFingerprintKey)
        return true
    }

    /// Forces the next change-gate call to report a change and rewrite the
    /// full payload. For partial writers outside Today (e.g. a completed
    /// analysis updating lastScore) that must not leave the gate believing
    /// the widget payload is already current.
    static func resetTodayFingerprint() {
        defaults?.removeObject(forKey: stateFingerprintKey)
    }

    // MARK: - Story Data

    static func updateLatestStory(title: String, storyCount: Int) {
        defaults?.set(title, forKey: "latestStoryTitle")
        defaults?.set(storyCount, forKey: "storyCount")
    }
}

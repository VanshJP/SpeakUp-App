import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID
    var defaultDuration: Int // 30, 60, 90, 120
    var dailyReminderEnabled: Bool
    var dailyReminderHour: Int
    var dailyReminderMinute: Int
    var weeklyGoalSessions: Int
    var exportFormat: ExportFormat
    var showOverallScore: Bool
    var showClarity: Bool
    var showPace: Bool
    var showFillerCount: Bool
    var showImprovement: Bool
    var hasCompletedOnboarding: Bool

    // Analysis Features
    var trackPauses: Bool
    var trackFillerWords: Bool

    // Prompt Settings
    var showDailyPrompt: Bool
    var enabledPromptCategories: [String] // Store category raw values

    // Weekly Summary
    var lastWeeklySummaryDate: Date?

    // Countdown Settings
    var countdownDuration: Int // 5, 10, 15, 20, 30 seconds
    var countdownStyle: Int = 0 // 0 = count down, 1 = count up

    // Timer End Behavior
    var timerEndBehavior: Int = 0 // 0 = save & stop, 1 = keep going

    // Word Bank
    var vocabWords: [String] = []

    init(
        id: UUID = UUID(),
        defaultDuration: Int = 60,
        dailyReminderEnabled: Bool = false,
        dailyReminderHour: Int = 9,
        dailyReminderMinute: Int = 0,
        weeklyGoalSessions: Int = 5,
        exportFormat: ExportFormat = .portrait,
        showOverallScore: Bool = true,
        showClarity: Bool = true,
        showPace: Bool = true,
        showFillerCount: Bool = true,
        showImprovement: Bool = true,
        hasCompletedOnboarding: Bool = false,
        trackPauses: Bool = true,
        trackFillerWords: Bool = true,
        showDailyPrompt: Bool = true,
        enabledPromptCategories: [String]? = nil,
        countdownDuration: Int = 15,
        countdownStyle: Int = 0,
        timerEndBehavior: Int = 0,
        vocabWords: [String] = []
    ) {
        self.id = id
        self.defaultDuration = defaultDuration
        self.dailyReminderEnabled = dailyReminderEnabled
        self.dailyReminderHour = dailyReminderHour
        self.dailyReminderMinute = dailyReminderMinute
        self.weeklyGoalSessions = weeklyGoalSessions
        self.exportFormat = exportFormat
        self.showOverallScore = showOverallScore
        self.showClarity = showClarity
        self.showPace = showPace
        self.showFillerCount = showFillerCount
        self.showImprovement = showImprovement
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.trackPauses = trackPauses
        self.trackFillerWords = trackFillerWords
        self.showDailyPrompt = showDailyPrompt
        // Default to all categories enabled
        self.enabledPromptCategories = enabledPromptCategories ?? PromptCategory.allCases.map { $0.rawValue }
        self.countdownDuration = countdownDuration
        self.countdownStyle = countdownStyle
        self.timerEndBehavior = timerEndBehavior
        self.vocabWords = vocabWords
    }
    
    var dailyReminderTime: DateComponents {
        var components = DateComponents()
        components.hour = dailyReminderHour
        components.minute = dailyReminderMinute
        return components
    }
    
    var formattedReminderTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var components = DateComponents()
        components.hour = dailyReminderHour
        components.minute = dailyReminderMinute
        
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(dailyReminderHour):\(String(format: "%02d", dailyReminderMinute))"
    }
    
    // Helper to check if a category is enabled
    func isCategoryEnabled(_ category: PromptCategory) -> Bool {
        enabledPromptCategories.contains(category.rawValue)
    }
    
    // Helper to toggle a category
    func toggleCategory(_ category: PromptCategory) {
        if isCategoryEnabled(category) {
            enabledPromptCategories.removeAll { $0 == category.rawValue }
        } else {
            enabledPromptCategories.append(category.rawValue)
        }
    }
    
    // Helper to get enabled categories as enum values
    var enabledCategories: [PromptCategory] {
        enabledPromptCategories.compactMap { PromptCategory(rawValue: $0) }
    }

    // MARK: - Word Bank Helpers

    func addVocabWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !vocabWords.contains(trimmed) else { return }
        vocabWords.append(trimmed)
    }

    func removeVocabWord(_ word: String) {
        vocabWords.removeAll { $0 == word }
    }
}

// MARK: - Export Format

enum ExportFormat: String, Codable, CaseIterable {
    case portrait = "9:16"
    case square = "1:1"
    case landscape = "16:9"

    var displayName: String {
        switch self {
        case .portrait: return "Portrait (9:16)"
        case .square: return "Square (1:1)"
        case .landscape: return "Landscape (16:9)"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .portrait: return 9.0 / 16.0
        case .square: return 1.0
        case .landscape: return 16.0 / 9.0
        }
    }
}

// MARK: - Timer End Behavior

enum TimerEndBehavior: Int, Codable, CaseIterable, Identifiable {
    case saveAndStop = 0
    case keepGoing = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .saveAndStop: return "Save & Stop"
        case .keepGoing: return "Keep Going"
        }
    }

    var description: String {
        switch self {
        case .saveAndStop: return "Auto-save when timer reaches zero"
        case .keepGoing: return "Continue recording past the timer"
        }
    }
}

// MARK: - Countdown Style

enum CountdownStyle: Int, Codable, CaseIterable, Identifiable {
    case countUp = 0
    case countDown = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .countUp: return "Count Up"
        case .countDown: return "Count Down"
        }
    }
}

// MARK: - Countdown Duration

enum CountdownDuration: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case twenty = 20
    case thirty = 30

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)s"
    }
}

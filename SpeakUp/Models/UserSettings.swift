import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID = UUID()
    var defaultDuration: Int = 60
    var dailyReminderEnabled: Bool = false
    var dailyReminderHour: Int = 9
    var dailyReminderMinute: Int = 0
    var weeklyGoalSessions: Int = 5
    var exportFormat: ExportFormat = ExportFormat.portrait
    var showOverallScore: Bool = true
    var showClarity: Bool = true
    var showPace: Bool = true
    var showFillerCount: Bool = true
    var showImprovement: Bool = true
    var hasCompletedOnboarding: Bool = false

    // Analysis Features
    var trackPauses: Bool = true
    var trackFillerWords: Bool = true

    // Prompt Settings
    var showDailyPrompt: Bool = true
    var enabledPromptCategories: [String] = []

    // Weekly Summary
    var lastWeeklySummaryDate: Date?

    // Countdown Settings
    var countdownDuration: Int = 10
    var countdownStyle: Int = 0 // 0 = count down, 1 = count up

    // Timer End Behavior
    var timerEndBehavior: Int = 0 // 0 = save & stop, 1 = keep going

    // Word Bank
    var vocabWords: [String] = []
    var dictationBiasWords: [String] = []

    // Target Pace
    var targetWPM: Int = 150

    // Haptic Coaching
    var hapticCoachingEnabled: Bool = false

    // Audio Cues
    var chirpSoundEnabled: Bool = true

    // Prompt Filtering
    var hideAnsweredPrompts: Bool = false

    // Listen Back
    var listenBackCount: Int = 0

    // Session Feedback
    var sessionFeedbackEnabled: Bool = true
    var customFeedbackQuestions: [FeedbackQuestion] = []

    // Filler Word Customization
    var customFillerWords: [String] = []              // user-added always-detected fillers
    var customContextFillerWords: [String] = []       // user-added context-dependent fillers
    var removedDefaultFillers: [String] = []          // default fillers the user disabled

    // Voice Profile
    var voiceProfileF0Hz: Double?
    var voiceProfileEnergyDb: Double?
    var voiceProfileSampleCount: Int = 0
    var voiceProfileLastUpdated: Date?

    // Story Practice
    var storyPracticeEnabled: Bool = false

    // iCloud Sync
    var iCloudSyncEnabled: Bool = false

    // Score Weights
    var clarityWeight: Double = 0.18
    var paceWeight: Double = 0.12
    var fillerWeight: Double = 0.14
    var pauseWeight: Double = 0.12
    var vocalVarietyWeight: Double = 0.12
    var deliveryWeight: Double = 0.10
    var vocabularyWeight: Double = 0.08
    var structureWeight: Double = 0.08
    var relevanceWeight: Double = 0.06

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
        countdownDuration: Int = 10,
        countdownStyle: Int = 0,
        timerEndBehavior: Int = 0,
        vocabWords: [String] = [],
        dictationBiasWords: [String] = []
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
        self.dictationBiasWords = dictationBiasWords
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
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !vocabWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        vocabWords.append(trimmed)
    }

    func removeVocabWord(_ word: String) {
        vocabWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    // MARK: - Dictation Dictionary Helpers

    func addDictationBiasWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !dictationBiasWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        dictationBiasWords.append(trimmed)
    }

    func removeDictationBiasWord(_ word: String) {
        dictationBiasWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
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

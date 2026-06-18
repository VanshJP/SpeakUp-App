import Foundation
import SwiftData
import SwiftUI

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
    var hideAnsweredPrompts: Bool = true

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

    // Dictation
    var autoFormatDictation: Bool = true

    // First Recording Setup
    var hasShownFirstRecordingSetup: Bool = false

    // iCloud Sync
    var iCloudSyncEnabled: Bool = false

    // Speaker Level (drives daily-prompt difficulty weighting)
    // Stored as raw Int so SwiftData lightweight migration handles older
    // databases without a manual migration step.
    var speakerLevel: Int = SpeakerLevel.intermediate.rawValue

    // User identity (captured during onboarding, used for personalised copy
    // and seeded into the dictation dictionary so transcripts spell it right).
    var userName: String = ""

    // Primary practice goal selected during onboarding. Drives default prompt
    // category mix on first run. Stored as raw Int for lightweight migration.
    var onboardingGoalRaw: Int = OnboardingGoal.everydayConfidence.rawValue

    // Onboarding resume support — last reached step so a force-quit mid-flow
    // resumes where the user left off instead of restarting from welcome.
    var onboardingStepRaw: Int = 0

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

    // MARK: - Dictation Dictionary Helpers

    func addDictationBiasWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !dictationBiasWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        dictationBiasWords.append(trimmed)
    }

    // MARK: - Speaker Level

    var resolvedSpeakerLevel: SpeakerLevel {
        SpeakerLevel(rawValue: speakerLevel) ?? .intermediate
    }

    // MARK: - Transcription Bias

    /// Unified list of user-defined terms to bias Whisper transcription toward.
    /// Combines the user's name, the dictation dictionary, the vocabulary word
    /// bank, and custom filler words (always-detected and context-dependent).
    /// De-duplicated case-insensitively; the name leads, followed by the
    /// dictation dictionary, so the most deliberate user entries front the
    /// prompt. The name is always included so transcripts spell it correctly.
    var transcriptionBiasTerms: [String] {
        let sources: [[String]] = [
            [userName],
            dictationBiasWords,
            vocabWords,
            customFillerWords,
            customContextFillerWords
        ]
        var seen: Set<String> = []
        var unique: [String] = []
        for source in sources {
            for term in source {
                let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if seen.insert(key).inserted {
                    unique.append(trimmed)
                }
            }
        }
        return unique
    }
}

// MARK: - Speaker Level

enum SpeakerLevel: Int, Codable, CaseIterable, Identifiable {
    case beginner = 0
    case intermediate = 1
    case advanced = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .beginner: return "New to public speaking. Build confidence with easy prompts."
        case .intermediate: return "Comfortable speaking. Mix of everyday and challenging prompts."
        case .advanced: return "Experienced speaker. Push limits with harder prompts."
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .intermediate: return "flame.fill"
        case .advanced: return "crown.fill"
        }
    }

    /// Three distinct muted-jewel identities so the onboarding level picker
    /// reads as a real choice between paths rather than a single tonal slide.
    var color: Color {
        switch self {
        case .beginner: return AppColors.categorySage
        case .intermediate: return AppColors.categoryTeal
        case .advanced: return AppColors.categoryPlum
        }
    }

    /// Weighted distribution of (easy, medium, hard) prompts for daily
    /// rotation. Higher weight = more frequent on the home screen.
    var dailyDifficultyWeights: (easy: Int, medium: Int, hard: Int) {
        switch self {
        case .beginner:     return (easy: 6, medium: 3, hard: 1)
        case .intermediate: return (easy: 3, medium: 5, hard: 2)
        case .advanced:     return (easy: 1, medium: 3, hard: 6)
        }
    }
}

// MARK: - Onboarding Goal

/// What the user wants out of SpeakUp. Drives default prompt category mix on
/// first launch and is shown back to the user on Today as gentle context.
enum OnboardingGoal: Int, Codable, CaseIterable, Identifiable {
    case interviews = 0
    case meetings = 1
    case presentations = 2
    case everydayConfidence = 3
    case storytelling = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .interviews: return "Ace Interviews"
        case .meetings: return "Lead Meetings"
        case .presentations: return "Nail Presentations"
        case .everydayConfidence: return "Everyday Confidence"
        case .storytelling: return "Tell Better Stories"
        }
    }

    var subtitle: String {
        switch self {
        case .interviews: return "Crisp answers, no filler, calm under pressure."
        case .meetings: return "Speak up, stay concise, drive the room."
        case .presentations: return "Pace, structure, and stage-ready delivery."
        case .everydayConfidence: return "Sound clearer in any conversation."
        case .storytelling: return "Narrative arc, beats, and emotion."
        }
    }

    var icon: String {
        switch self {
        case .interviews: return "briefcase.fill"
        case .meetings: return "person.3.fill"
        case .presentations: return "rectangle.on.rectangle.angled"
        case .everydayConfidence: return "sparkles"
        case .storytelling: return "book.pages.fill"
        }
    }

    /// One muted-jewel tone per goal so the onboarding goal picker shows
    /// five distinct identities. All tones live in the same desaturated band
    /// so the screen stays cohesive on glass.
    var color: Color {
        switch self {
        case .interviews:
            return AppColors.categoryTeal
        case .meetings:
            return AppColors.categoryIndigo
        case .presentations:
            return AppColors.categoryCopper
        case .everydayConfidence:
            return AppColors.categorySage
        case .storytelling:
            return AppColors.categoryPlum
        }
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

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

    var trackPauses: Bool = true
    var trackFillerWords: Bool = true

    var showDailyPrompt: Bool = true
    var enabledPromptCategories: [String] = []

    var lastWeeklySummaryDate: Date?

    var countdownDuration: Int = 10
    var countdownStyle: Int = 0 // 0 = count down, 1 = count up

    var timerEndBehavior: Int = 0 // 0 = save & stop, 1 = keep going

    // Look & feel — cosmetic only, raw values of the enums named in comments
    var waveformStyle: Int = 0      // WaveformStyle
    var recordButtonStyle: Int = 0  // RecordButtonStyle
    var countdownLook: Int = 0      // TimerLook
    var countdownBackdrop: Int = 0  // RecordingBackdrop — column name predates it covering the whole session
    var soundPack: Int = 0          // SoundPack (ChirpPlayer.swift)
    var shareCardTheme: Int = 0     // ScoreCardTheme (ScoreCardRenderer.swift)

    // App appearance — additive. Light glass + Classic canvas match the
    // post-brighten default; Dark glass restores the deeper pre-brighten look.
    var glassAppearance: Int = 0    // GlassAppearance
    var appCanvas: Int = 0          // AppCanvas

    var vocabWords: [String] = []
    var dictationBiasWords: [String] = []

    var targetWPM: Int = 150

    var autoPaceTarget: Bool = true
    var calibratedWPM: Double?

    var hapticCoachingEnabled: Bool = false

    var chirpSoundEnabled: Bool = true

    var hideAnsweredPrompts: Bool = true

    var listenBackCount: Int = 0

    /// Ask after each session before showing the score. Defaults off so the
    /// first scored take is never blocked by a questionnaire (activation moment).
    /// Users who want the self-check can enable it in Session Defaults.
    var sessionFeedbackEnabled: Bool = false
    var customFeedbackQuestions: [FeedbackQuestion] = []

    var customFillerWords: [String] = []              // user-added always-detected fillers
    var customContextFillerWords: [String] = []       // user-added context-dependent fillers
    var removedDefaultFillers: [String] = []          // default fillers the user disabled

    var voiceProfileF0Hz: Double?
    var voiceProfileEnergyDb: Double?
    var voiceProfileSampleCount: Int = 0
    var voiceProfileLastUpdated: Date?

    var storyPracticeEnabled: Bool = false

    // Daily word workout. Additive defaults so existing rows keep the feature
    // on and mix bank + dictionary + a new word each day.
    var vocabChallengeEnabled: Bool = true
    var vocabChallengeWordCount: Int = 2
    var vocabChallengeUseBank: Bool = true
    var vocabChallengeUseDictionary: Bool = true
    var vocabChallengeIntroduceNew: Bool = true
    var vocabChallengeSpacedReview: Bool = true
    var vocabChallengeLevelOverride: Int = 0

    var autoFormatDictation: Bool = true

    var hasShownFirstRecordingSetup: Bool = false

    var hasSeenAppTour: Bool = false

    // Today home layout — ordered raw values of visible `TodayHomeModule`s.
    // Empty means factory default (never customized). Session is always forced
    // visible by `TodayHomeLayout.resolve`. Additive; see today-library.md.
    var todayHomeLayoutRaw: [String] = []

    // Coach notes — weekly celebration budget + delivery memory.
    // Additive defaults: empty week key / zero used / empty lists mean "never
    // shown a celebration note yet". See docs/features/coach-moments.md.
    var coachMomentWeekKey: String = ""
    var coachMomentCelebrationsUsedThisWeek: Int = 0
    var coachMomentDeliveredIDs: [String] = []
    var coachMomentClearedDimensionsRaw: [String] = []

    var iCloudSyncEnabled: Bool = false

    // Speaker Level (drives daily-prompt difficulty weighting)
    // Stored as raw Int so SwiftData lightweight migration handles older
    // databases without a manual migration step.
    var speakerLevel: Int = SpeakerLevel.intermediate.rawValue

    var userName: String = ""

    var onboardingGoalRaw: Int = OnboardingGoal.everydayConfidence.rawValue

    // Every goal picked during onboarding, in pick order. Weights which prompt
    // categories surface on Today (see `PromptMix`). Additive with an empty
    // default so existing rows migrate without a schema step; an empty array
    // means "this row predates multi-select" and falls back to the single goal.
    var onboardingGoalsRaw: [Int] = []

    // Legacy, unread. Onboarding resume moved to UserDefaults
    // (`onboarding.lastReachedStep.*`) so drafts don't touch the SwiftData
    // store. Kept because removing a stored attribute breaks lightweight
    // migration and CloudKit schema evolution for existing installs.
    var onboardingStepRaw: Int = 0

    // Legacy, unread. The immediate three-analysis intro grant was replaced by
    // the 14-day trial, whose clock lives in `EntitlementStore`. Kept because
    // removing a stored attribute breaks lightweight migration and CloudKit
    // schema evolution for existing installs.
    var freeIntroAnalysesUsed: Int = 0

    // Free-tier analysis allowance, used once the trial has expired. Counters
    // only — whether they are consulted at all is decided by
    // `EntitlementStore.policy`.
    var freeCycleStart: Date?
    var freeCycleAnalysesUsed: Int = 0

    var hasSeenPaywall: Bool = false
    var lastReviewRequestVersion: String?
    var lastReviewRequestDate: Date?

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
        self.enabledPromptCategories = enabledPromptCategories ?? PromptCategory.allCases.map { $0.rawValue }
        self.countdownDuration = countdownDuration
        self.countdownStyle = countdownStyle
        self.timerEndBehavior = timerEndBehavior
        self.vocabWords = vocabWords
        self.dictationBiasWords = dictationBiasWords
    }
    
    var enabledCategories: [PromptCategory] {
        enabledPromptCategories.compactMap { PromptCategory(rawValue: $0) }
    }

    var todayHomeModules: [TodayHomeModule] {
        TodayHomeLayout.resolve(todayHomeLayoutRaw)
    }

    var coachMomentBudget: CoachMomentBudget {
        CoachMomentBudget(
            weekKey: coachMomentWeekKey,
            celebrationsUsed: coachMomentCelebrationsUsedThisWeek,
            deliveredIDs: coachMomentDeliveredIDs
        ).rolling(now: .now)
    }

    func apply(budget: CoachMomentBudget) {
        coachMomentWeekKey = budget.weekKey
        coachMomentCelebrationsUsedThisWeek = budget.celebrationsUsed
        coachMomentDeliveredIDs = budget.deliveredIDs
    }

    // MARK: - Pace Target Resolution

    var resolvedTargetWPM: Int {
        guard autoPaceTarget, let calibrated = calibratedWPM else { return targetWPM }
        return Int(calibrated.rounded())
    }

    // MARK: - Word Bank Helpers

    func addVocabWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordSafety.allows(trimmed) else { return }
        guard !vocabWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        vocabWords.append(trimmed)
    }

    // MARK: - Dictation Dictionary Helpers

    func addDictationBiasWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordSafety.allows(trimmed) else { return }
        guard !dictationBiasWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        dictationBiasWords.append(trimmed)
    }

    var vocabChallengePreferences: VocabChallengePreferences {
        VocabChallengePreferences(
            isEnabled: vocabChallengeEnabled,
            wordCount: vocabChallengeWordCount,
            useBank: vocabChallengeUseBank,
            useDictionary: vocabChallengeUseDictionary,
            introduceNew: vocabChallengeIntroduceNew,
            spacedReviewEnabled: vocabChallengeSpacedReview,
            vocabWords: vocabWords,
            dictionaryWords: dictationBiasWords,
            extraBanned: customFillerWords + customContextFillerWords,
            userName: userName,
            speakerLevelRaw: speakerLevel,
            levelOverrideRaw: vocabChallengeLevelOverride
        )
    }

    // MARK: - Speaker Level

    var resolvedSpeakerLevel: SpeakerLevel {
        SpeakerLevel(rawValue: speakerLevel) ?? .intermediate
    }

    // MARK: - Practice Goals

    /// Goals picked during onboarding, in pick order. Falls back to the single
    /// stored goal for rows written before multi-select existed, so the prompt
    /// mix is never empty for an upgrading user.
    var resolvedOnboardingGoals: [OnboardingGoal] {
        let picked = onboardingGoalsRaw.compactMap { OnboardingGoal(rawValue: $0) }
        if !picked.isEmpty { return picked }
        return [OnboardingGoal(rawValue: onboardingGoalRaw) ?? .everydayConfidence]
    }

    var promptMix: PromptMix {
        PromptMix(
            goals: resolvedOnboardingGoals,
            enabledCategoryNames: Set(enabledPromptCategories)
        )
    }

    // MARK: - Free-Tier Allowance

    var allowanceState: AllowanceState {
        get {
            AllowanceState(
                cycleStart: freeCycleStart,
                cycleUsed: freeCycleAnalysesUsed
            )
        }
        set {
            freeCycleStart = newValue.cycleStart
            freeCycleAnalysesUsed = newValue.cycleUsed
        }
    }

    // MARK: - Transcription Bias

    /// Unified list of user-defined terms to bias Whisper transcription toward.
    /// De-duplicated case-insensitively; the name leads, followed by the
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

extension Optional where Wrapped == UserSettings {
    var resolvedTargetWPM: Int { self?.resolvedTargetWPM ?? 150 }
}

extension ScoreWeights {
    /// User-tuned weights from settings; defaults when settings don't exist yet.
    init(from settings: UserSettings?) {
        guard let settings else {
            self = .defaults
            return
        }
        self.init(
            clarity: settings.clarityWeight,
            pace: settings.paceWeight,
            filler: settings.fillerWeight,
            pause: settings.pauseWeight,
            vocalVariety: settings.vocalVarietyWeight,
            delivery: settings.deliveryWeight,
            vocabulary: settings.vocabularyWeight,
            structure: settings.structureWeight,
            relevance: settings.relevanceWeight
        )
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

    var dailyDifficultyWeights: (easy: Int, medium: Int, hard: Int) {
        switch self {
        case .beginner:     return (easy: 6, medium: 3, hard: 1)
        case .intermediate: return (easy: 3, medium: 5, hard: 2)
        case .advanced:     return (easy: 1, medium: 3, hard: 6)
        }
    }
}

// MARK: - Onboarding Goal

enum OnboardingGoal: Int, Codable, CaseIterable, Identifiable {
    case interviews = 0
    case meetings = 1
    case presentations = 2
    case everydayConfidence = 3
    case storytelling = 4

    var id: Int { rawValue }

    /// Plain nouns naming the situation. These used to be verb phrases ("Ace
    /// Interviews", "Nail Presentations") mixed with one noun phrase, which is
    /// pitch-deck voice rather than product voice.
    var displayName: String {
        switch self {
        case .interviews: return "Interviews"
        case .meetings: return "Meetings"
        case .presentations: return "Presentations"
        case .everydayConfidence: return "Everyday talk"
        case .storytelling: return "Storytelling"
        }
    }

    var subtitle: String {
        switch self {
        case .interviews: return "Questions you have to answer well the first time."
        case .meetings: return "Say your piece without padding it."
        case .presentations: return "Longer answers you shape before you speak."
        case .everydayConfidence: return "Ordinary topics, nothing riding on it."
        case .storytelling: return "Tell what happened and keep them listening."
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

// MARK: - Waveform Style

enum WaveformStyle: Int, Codable, CaseIterable, Identifiable {
    case rings = 0
    case bars = 1
    case dots = 2
    case ribbon = 3
    case pulse = 4
    case spark = 5
    /// Named `off`, not `none`, so `.none` never reads as an Optional here.
    case off = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .rings: return "Rings"
        case .bars: return "Bars"
        case .dots: return "Dots"
        case .ribbon: return "Ribbon"
        case .pulse: return "Pulse"
        case .spark: return "Spark"
        case .off: return "Off"
        }
    }
}

// MARK: - Record Button Style

enum RecordButtonStyle: Int, Codable, CaseIterable, Identifiable {
    case classic = 0
    case ring = 1
    case orb = 2
    case minimal = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .ring: return "Ring"
        case .orb: return "Orb"
        case .minimal: return "Minimal"
        }
    }
}

// MARK: - Timer Look

enum TimerLook: Int, Codable, CaseIterable, Identifiable {
    case ring = 0
    case orb = 1
    case segments = 2
    case minimal = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .ring: return "Ring"
        case .orb: return "Orb"
        case .segments: return "Segments"
        case .minimal: return "Minimal"
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

import Foundation
import SwiftUI
import SwiftData

@MainActor @Observable
class SettingsViewModel {
    var settings: UserSettings?
    var isLoading = true
    var showingResetConfirmation = false
    var showingClearDataConfirmation = false
    var clearDataAcknowledgement = ""
    
    // Local state for pickers - Recording Defaults
    var defaultDuration: RecordingDuration = .sixty
    
    // Local state - Reminders
    var dailyReminderEnabled: Bool = false
    var reminderTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    
    // Local state - Goals
    var weeklyGoalSessions: Int = 5
    
    // Local state - Analysis Features
    var trackPauses: Bool = true
    var trackFillerWords: Bool = true
    var targetWPM: Int = 150
    
    // Local state - Prompt Settings
    var showDailyPrompt: Bool = true
    var enabledPromptCategories: Set<PromptCategory> = Set(PromptCategory.allCases)

    // Local state - Prompt Filtering
    var hideAnsweredPrompts: Bool = false

    // Local state - Countdown
    var countdownDuration: CountdownDuration = .fifteen
    var countdownStyle: CountdownStyle = .countDown

    // Local state - Timer End Behavior
    var timerEndBehavior: TimerEndBehavior = .saveAndStop

    // Local state - Haptic Coaching
    var hapticCoachingEnabled: Bool = false

    // Local state - Audio Cues
    var chirpSoundEnabled: Bool = true

    // Local state - Session Feedback
    var sessionFeedbackEnabled: Bool = true
    var customFeedbackQuestions: [FeedbackQuestion] = []
    var showingAddFeedbackQuestion: Bool = false
    var newFeedbackQuestionText: String = ""
    var newFeedbackQuestionType: FeedbackQuestionType = .scale

    var activeFeedbackQuestions: [FeedbackQuestion] {
        DefaultFeedbackQuestions.questions + customFeedbackQuestions
    }

    // Local state - Score Weights
    var clarityWeight: Double = 0.18
    var paceWeight: Double = 0.12
    var fillerWeight: Double = 0.14
    var pauseWeight: Double = 0.12
    var vocalVarietyWeight: Double = 0.12
    var deliveryWeight: Double = 0.10
    var vocabularyWeight: Double = 0.08
    var structureWeight: Double = 0.08
    var relevanceWeight: Double = 0.06

    var hasCustomWeights: Bool {
        let d = ScoreWeights.defaults
        return clarityWeight != d.clarity || paceWeight != d.pace ||
               fillerWeight != d.filler || pauseWeight != d.pause ||
               vocalVarietyWeight != d.vocalVariety || deliveryWeight != d.delivery ||
               vocabularyWeight != d.vocabulary || structureWeight != d.structure ||
               relevanceWeight != d.relevance
    }

    // Local state - Word Bank
    var vocabWords: [String] = []
    var newVocabWord: String = ""
    var vocabWordError: String? = nil
    var showingAddVocabWord: Bool = false
    private var vocabErrorDismissID = 0
    var dictationBiasWords: [String] = []
    var newDictationBiasWord: String = ""
    var dictationWordError: String? = nil
    private var dictationErrorDismissID = 0

    /// Terms used to bias Whisper toward names/domain words.
    var whisperDictionaryWords: [String] {
        dictationBiasWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // Local state - Filler Words
    var customFillerWords: [String] = []
    var customContextFillerWords: [String] = []
    var removedDefaultFillers: [String] = []
    var newFillerWord: String = ""
    var fillerWordError: String? = nil
    private var fillerErrorDismissID = 0

    /// All active filler words (defaults minus removed + custom), sorted.
    var activeFillerWords: [(word: String, isCustom: Bool, isContextDependent: Bool)] {
        let removed = Set(removedDefaultFillers)

        var result: [(word: String, isCustom: Bool, isContextDependent: Bool)] = []

        // Default unconditional fillers (not removed)
        for word in FillerWordList.unconditionalFillers where !removed.contains(word) {
            result.append((word: word, isCustom: false, isContextDependent: false))
        }

        // Default context-dependent fillers (not removed)
        for word in FillerWordList.contextDependentFillers where !removed.contains(word) {
            result.append((word: word, isCustom: false, isContextDependent: true))
        }

        // Custom always-detected fillers
        for word in customFillerWords {
            result.append((word: word, isCustom: true, isContextDependent: false))
        }

        // Custom context-dependent fillers
        for word in customContextFillerWords {
            result.append((word: word, isCustom: true, isContextDependent: true))
        }

        return result.sorted { $0.word < $1.word }
    }

    var hasFillerCustomizations: Bool {
        !customFillerWords.isEmpty || !customContextFillerWords.isEmpty || !removedDefaultFillers.isEmpty
    }

    /// Build a FillerWordConfig from current state.
    var fillerWordConfig: FillerWordConfig {
        FillerWordConfig(
            customFillers: Set(customFillerWords),
            customContextFillers: Set(customContextFillerWords),
            removedDefaults: Set(removedDefaultFillers)
        )
    }

    private var modelContext: ModelContext?
    private var hasConfigured = false
    var isSyncing = false
    private let notificationService = NotificationService()

    func configure(with context: ModelContext) {
        guard !hasConfigured else { return }
        hasConfigured = true
        self.modelContext = context
        Task {
            await loadSettings()
        }
    }

    func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<UserSettings>()
        
        do {
            if let existingSettings = try context.fetch(descriptor).first {
                settings = existingSettings
                syncLocalState()
            } else {
                // Create default settings
                let newSettings = UserSettings()
                context.insert(newSettings)
                try context.save()
                settings = newSettings
                syncLocalState()
            }
        } catch {
            print("Error loading settings: \(error)")
        }
    }
    
    private func syncLocalState() {
        guard let settings else { return }

        isSyncing = true
        defer { isSyncing = false }

        defaultDuration = RecordingDuration(rawValue: settings.defaultDuration) ?? .sixty
        dailyReminderEnabled = settings.dailyReminderEnabled

        var components = DateComponents()
        components.hour = settings.dailyReminderHour
        components.minute = settings.dailyReminderMinute
        reminderTime = Calendar.current.date(from: components) ?? Date()

        weeklyGoalSessions = settings.weeklyGoalSessions

        // Analysis features
        trackPauses = settings.trackPauses
        trackFillerWords = settings.trackFillerWords
        targetWPM = settings.targetWPM

        // Prompt settings
        showDailyPrompt = settings.showDailyPrompt
        hideAnsweredPrompts = settings.hideAnsweredPrompts
        enabledPromptCategories = Set(settings.enabledCategories)

        // Countdown duration & style
        countdownDuration = CountdownDuration(rawValue: settings.countdownDuration) ?? .fifteen
        countdownStyle = CountdownStyle(rawValue: settings.countdownStyle) ?? .countDown

        // Timer end behavior
        timerEndBehavior = TimerEndBehavior(rawValue: settings.timerEndBehavior) ?? .saveAndStop

        // Word Bank
        vocabWords = settings.vocabWords
        dictationBiasWords = settings.dictationBiasWords

        // Filler Words
        customFillerWords = settings.customFillerWords
        customContextFillerWords = settings.customContextFillerWords
        removedDefaultFillers = settings.removedDefaultFillers

        // Haptic Coaching
        hapticCoachingEnabled = settings.hapticCoachingEnabled

        // Audio Cues
        chirpSoundEnabled = settings.chirpSoundEnabled
        ChirpPlayer.shared.isEnabled = settings.chirpSoundEnabled

        // Session Feedback
        sessionFeedbackEnabled = settings.sessionFeedbackEnabled
        customFeedbackQuestions = settings.customFeedbackQuestions

        // Score Weights
        clarityWeight = settings.clarityWeight
        paceWeight = settings.paceWeight
        fillerWeight = settings.fillerWeight
        pauseWeight = settings.pauseWeight
        vocalVarietyWeight = settings.vocalVarietyWeight
        deliveryWeight = settings.deliveryWeight
        vocabularyWeight = settings.vocabularyWeight
        structureWeight = settings.structureWeight
        relevanceWeight = settings.relevanceWeight
    }
    
    @MainActor
    func saveSettings() async {
        guard let settings, let context = modelContext else { return }

        settings.defaultDuration = defaultDuration.rawValue
        settings.dailyReminderEnabled = dailyReminderEnabled
        
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        settings.dailyReminderHour = components.hour ?? 9
        settings.dailyReminderMinute = components.minute ?? 0
        
        settings.weeklyGoalSessions = weeklyGoalSessions

        // Analysis features
        settings.trackPauses = trackPauses
        settings.trackFillerWords = trackFillerWords
        settings.targetWPM = targetWPM
        
        // Prompt settings
        settings.showDailyPrompt = showDailyPrompt
        settings.hideAnsweredPrompts = hideAnsweredPrompts
        settings.enabledPromptCategories = enabledPromptCategories.map { $0.rawValue }

        // Countdown duration & style
        settings.countdownDuration = countdownDuration.rawValue
        settings.countdownStyle = countdownStyle.rawValue

        // Timer end behavior
        settings.timerEndBehavior = timerEndBehavior.rawValue

        // Word Bank
        settings.vocabWords = vocabWords
        settings.dictationBiasWords = dictationBiasWords

        // Filler Words
        settings.customFillerWords = customFillerWords
        settings.customContextFillerWords = customContextFillerWords
        settings.removedDefaultFillers = removedDefaultFillers

        // Haptic Coaching
        settings.hapticCoachingEnabled = hapticCoachingEnabled

        // Audio Cues
        settings.chirpSoundEnabled = chirpSoundEnabled
        ChirpPlayer.shared.isEnabled = chirpSoundEnabled

        // Session Feedback
        settings.sessionFeedbackEnabled = sessionFeedbackEnabled
        settings.customFeedbackQuestions = customFeedbackQuestions

        // Score Weights
        settings.clarityWeight = clarityWeight
        settings.paceWeight = paceWeight
        settings.fillerWeight = fillerWeight
        settings.pauseWeight = pauseWeight
        settings.vocalVarietyWeight = vocalVarietyWeight
        settings.deliveryWeight = deliveryWeight
        settings.vocabularyWeight = vocabularyWeight
        settings.structureWeight = structureWeight
        settings.relevanceWeight = relevanceWeight

        do {
            try context.save()
            
            // Update notifications if needed
            if dailyReminderEnabled {
                await scheduleReminderNotification()
            } else {
                await cancelReminderNotification()
            }
        } catch {
            print("Error saving settings: \(error)")
        }
    }
    
    @MainActor
    func toggleCategory(_ category: PromptCategory) {
        if enabledPromptCategories.contains(category) {
            // Don't allow disabling all categories
            if enabledPromptCategories.count > 1 {
                enabledPromptCategories.remove(category)
            }
        } else {
            enabledPromptCategories.insert(category)
        }
        Task {
            await saveSettings()
        }
    }
    
    func isCategoryEnabled(_ category: PromptCategory) -> Bool {
        enabledPromptCategories.contains(category)
    }

    // MARK: - Word Bank

    @MainActor
    func addVocabWord() {
        vocabWordError = nil
        let trimmed = newVocabWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newVocabWord = ""
            return
        }
        guard !vocabWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            showVocabError("Already in your word bank")
            return
        }
        guard !isFillerWord(trimmed) else {
            showVocabError("That's a filler word — we track those separately")
            return
        }
        guard trimmed.count >= 2 else {
            showVocabError("Use at least 2 characters")
            return
        }
        vocabWords.append(trimmed)
        newVocabWord = ""
        Haptics.success()
        Task { await saveSettings() }
    }

    @MainActor
    private func showVocabError(_ message: String) {
        Haptics.warning()
        vocabWordError = message
        vocabErrorDismissID += 1
        let currentID = vocabErrorDismissID
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard currentID == vocabErrorDismissID else { return }
            vocabWordError = nil
        }
    }

    @MainActor
    func removeVocabWord(at offsets: IndexSet) {
        vocabWords.remove(atOffsets: offsets)
        Task { await saveSettings() }
    }

    @MainActor
    func removeVocabWord(_ word: String) {
        vocabWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        Task { await saveSettings() }
    }

    @MainActor
    func addDictationBiasWord() {
        dictationWordError = nil
        let trimmed = newDictationBiasWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newDictationBiasWord = ""
            return
        }
        guard trimmed.count >= 2 else {
            showDictationError("Use at least 2 characters")
            return
        }
        guard !dictationBiasWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            showDictationError("Already in your dictation dictionary")
            return
        }
        guard !isFillerWord(trimmed) else {
            showDictationError("That's a filler word — avoid biasing it")
            return
        }
        dictationBiasWords.append(trimmed)
        newDictationBiasWord = ""
        Haptics.success()
        Task { await saveSettings() }
    }

    @MainActor
    private func showDictationError(_ message: String) {
        Haptics.warning()
        dictationWordError = message
        dictationErrorDismissID += 1
        let currentID = dictationErrorDismissID
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard currentID == dictationErrorDismissID else { return }
            dictationWordError = nil
        }
    }

    @MainActor
    func removeDictationBiasWord(_ word: String) {
        dictationBiasWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        Task { await saveSettings() }
    }

    // MARK: - Filler Words

    @MainActor
    func addCustomFiller(isContextDependent: Bool = false) {
        fillerWordError = nil
        let trimmed = newFillerWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            newFillerWord = ""
            return
        }
        // Already a default filler?
        if FillerWordList.unconditionalFillers.contains(trimmed) || FillerWordList.contextDependentFillers.contains(trimmed) {
            // If it was removed, restore it instead
            if removedDefaultFillers.contains(trimmed) {
                restoreDefaultFiller(trimmed)
                newFillerWord = ""
                return
            }
            showFillerError("Already a default filler word")
            return
        }
        guard !customFillerWords.contains(trimmed), !customContextFillerWords.contains(trimmed) else {
            showFillerError("Already in your custom fillers")
            return
        }
        guard !vocabWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            showFillerError("This word is in your Word Bank")
            return
        }
        guard !dictationBiasWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            showFillerError("This word is in your Dictation Dictionary")
            return
        }
        if isContextDependent {
            customContextFillerWords.append(trimmed)
        } else {
            customFillerWords.append(trimmed)
        }
        newFillerWord = ""
        Haptics.success()
        Task { await saveSettings() }
    }

    @MainActor
    func removeFillerWord(_ word: String) {
        let lowered = word.lowercased()
        if customFillerWords.contains(lowered) {
            customFillerWords.removeAll { $0 == lowered }
        } else if customContextFillerWords.contains(lowered) {
            customContextFillerWords.removeAll { $0 == lowered }
        } else {
            // Default filler — add to removed list
            if !removedDefaultFillers.contains(lowered) {
                removedDefaultFillers.append(lowered)
            }
        }
        Haptics.light()
        Task { await saveSettings() }
    }

    @MainActor
    func restoreDefaultFiller(_ word: String) {
        removedDefaultFillers.removeAll { $0 == word.lowercased() }
        Haptics.success()
        Task { await saveSettings() }
    }

    @MainActor
    func resetFillersToDefaults() {
        customFillerWords = []
        customContextFillerWords = []
        removedDefaultFillers = []
        Haptics.success()
        Task { await saveSettings() }
    }

    @MainActor
    private func showFillerError(_ message: String) {
        Haptics.warning()
        fillerWordError = message
        fillerErrorDismissID += 1
        let currentID = fillerErrorDismissID
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard currentID == fillerErrorDismissID else { return }
            fillerWordError = nil
        }
    }

    // MARK: - Feedback Questions

    @MainActor
    func addFeedbackQuestion() {
        let trimmed = newFeedbackQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let question = FeedbackQuestion(text: trimmed, type: newFeedbackQuestionType)
        customFeedbackQuestions.append(question)
        newFeedbackQuestionText = ""
        newFeedbackQuestionType = .scale
        showingAddFeedbackQuestion = false
        Haptics.success()
        Task { await saveSettings() }
    }

    @MainActor
    func removeFeedbackQuestion(_ question: FeedbackQuestion) {
        customFeedbackQuestions.removeAll { $0.id == question.id }
        Haptics.light()
        Task { await saveSettings() }
    }

    private func isFillerWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        return FillerWordList.isFillerWord(lowered)
            || FillerWordList.contextDependentFillers.contains(lowered)
            || customFillerWords.contains(lowered)
            || customContextFillerWords.contains(lowered)
    }

    @MainActor
    func resetSettings() async {
        guard let settings, let context = modelContext else { return }

        // Reset to defaults
        settings.defaultDuration = 60
        settings.dailyReminderEnabled = false
        settings.dailyReminderHour = 9
        settings.dailyReminderMinute = 0
        settings.weeklyGoalSessions = 5
        settings.trackPauses = true
        settings.trackFillerWords = true
        settings.targetWPM = 150
        settings.showDailyPrompt = true
        settings.hideAnsweredPrompts = false
        settings.enabledPromptCategories = PromptCategory.allCases.map { $0.rawValue }
        settings.countdownDuration = 15
        settings.countdownStyle = 0
        settings.timerEndBehavior = 0
        settings.vocabWords = []
        settings.dictationBiasWords = []
        settings.customFillerWords = []
        settings.customContextFillerWords = []
        settings.removedDefaultFillers = []
        settings.chirpSoundEnabled = true
        settings.sessionFeedbackEnabled = true
        settings.customFeedbackQuestions = []

        // Score Weights
        let defaults = ScoreWeights.defaults
        settings.clarityWeight = defaults.clarity
        settings.paceWeight = defaults.pace
        settings.fillerWeight = defaults.filler
        settings.pauseWeight = defaults.pause
        settings.vocalVarietyWeight = defaults.vocalVariety
        settings.deliveryWeight = defaults.delivery
        settings.vocabularyWeight = defaults.vocabulary
        settings.structureWeight = defaults.structure
        settings.relevanceWeight = defaults.relevance

        do {
            try context.save()
            syncLocalState()
        } catch {
            print("Error resetting settings: \(error)")
        }
    }

    @MainActor
    func resetWeightsToDefaults() {
        let defaults = ScoreWeights.defaults
        clarityWeight = defaults.clarity
        paceWeight = defaults.pace
        fillerWeight = defaults.filler
        pauseWeight = defaults.pause
        vocalVarietyWeight = defaults.vocalVariety
        deliveryWeight = defaults.delivery
        vocabularyWeight = defaults.vocabulary
        structureWeight = defaults.structure
        relevanceWeight = defaults.relevance
        Task { await saveSettings() }
    }
    
    @MainActor
    func clearAllData() async {
        guard let context = modelContext else { return }

        do {
            // Delete all recordings and their files
            let recordingDescriptor = FetchDescriptor<Recording>()
            let recordings = try context.fetch(recordingDescriptor)
            for recording in recordings {
                if let audioURL = recording.audioURL {
                    try? FileManager.default.removeItem(at: audioURL)
                }
                if let videoURL = recording.videoURL {
                    try? FileManager.default.removeItem(at: videoURL)
                }
                context.delete(recording)
            }

            // Delete all goals
            let goalDescriptor = FetchDescriptor<UserGoal>()
            let goals = try context.fetch(goalDescriptor)
            for goal in goals {
                context.delete(goal)
            }

            // Delete all achievements
            let achievementDescriptor = FetchDescriptor<Achievement>()
            let achievements = try context.fetch(achievementDescriptor)
            for achievement in achievements {
                context.delete(achievement)
            }

            // Delete curriculum progress
            let curriculumDescriptor = FetchDescriptor<CurriculumProgress>()
            let curriculumItems = try context.fetch(curriculumDescriptor)
            for item in curriculumItems {
                context.delete(item)
            }

            // Clear word bank and filler customizations from settings
            if let settings {
                settings.vocabWords = []
                settings.dictationBiasWords = []
                settings.customFillerWords = []
                settings.customContextFillerWords = []
                settings.removedDefaultFillers = []
            }
            vocabWords = []
            dictationBiasWords = []
            customFillerWords = []
            customContextFillerWords = []
            removedDefaultFillers = []

            try context.save()
        } catch {
            print("Error clearing data: \(error)")
        }
    }
    
    // MARK: - Notification Helpers
    
    private func scheduleReminderNotification() async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        await notificationService.scheduleDailyReminder(hour: hour, minute: minute)
    }

    private func cancelReminderNotification() async {
        await notificationService.cancelDailyReminder()
    }
    
    // MARK: - App Info
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

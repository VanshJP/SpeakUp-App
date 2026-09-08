import Foundation
import os.log
import SwiftUI
import SwiftData

@MainActor @Observable
class SettingsViewModel {
    private let logger = Logger.app("Settings")
    var settings: UserSettings?
    var isLoading = true
    var showingResetConfirmation = false
    var showingClearDataConfirmation = false
    var showingVoiceProfileResetConfirmation = false
    var showingVoiceCalibration = false
    var clearDataAcknowledgement = ""
    
    var userName: String = ""

    var defaultDuration: RecordingDuration = .sixty
    
    var dailyReminderEnabled: Bool = false
    var reminderTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    
    var weeklyGoalSessions: Int = 5
    
    var trackPauses: Bool = true
    var trackFillerWords: Bool = true
    var targetWPM: Int = 150
    var autoPaceTarget: Bool = true
    
    var enabledPromptCategories: Set<PromptCategory> = Set(PromptCategory.allCases)

    var hideAnsweredPrompts: Bool = false

    var storyPracticeEnabled: Bool = false

    var vocabChallengeEnabled: Bool = true
    var vocabChallengeWordCount: Int = 2
    var vocabChallengeIntroduceNew: Bool = true
    var vocabChallengeLevelOverride: Int = 0

    var speakerLevel: SpeakerLevel = .intermediate

    var countdownDuration: CountdownDuration = .fifteen
    var countdownStyle: CountdownStyle = .countDown

    var timerEndBehavior: TimerEndBehavior = .saveAndStop

    var waveformStyle: WaveformStyle = .rings
    var recordButtonStyle: RecordButtonStyle = .classic
    var countdownLook: TimerLook = .ring
    var recordingBackdrop: RecordingBackdrop = .base

    var glassAppearance: GlassAppearance = .light
    var appCanvas: AppCanvas = .classic

    var soundPack: SoundPack = .soft

    var hapticCoachingEnabled: Bool = false

    var chirpSoundEnabled: Bool = true

    var sessionFeedbackEnabled: Bool = false
    var customFeedbackQuestions: [FeedbackQuestion] = []
    var showingAddFeedbackQuestion: Bool = false
    var newFeedbackQuestionText: String = ""
    var newFeedbackQuestionType: FeedbackQuestionType = .scale

    var activeFeedbackQuestions: [FeedbackQuestion] {
        DefaultFeedbackQuestions.questions + customFeedbackQuestions
    }

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

    var vocabWords: [String] = []
    var newVocabWord: String = ""
    var vocabWordError: String? = nil
    private var vocabErrorDismissID = 0
    var dictationBiasWords: [String] = []
    var newDictationBiasWord: String = ""
    var dictationWordError: String? = nil
    private var dictationErrorDismissID = 0

    var customFillerWords: [String] = []
    var customContextFillerWords: [String] = []
    var removedDefaultFillers: [String] = []
    var newFillerWord: String = ""
    var fillerWordError: String? = nil
    private var fillerErrorDismissID = 0

    var activeFillerWords: [(word: String, isCustom: Bool, isContextDependent: Bool)] {
        let removed = Set(removedDefaultFillers)

        var result: [(word: String, isCustom: Bool, isContextDependent: Bool)] = []

        for word in FillerWordList.unconditionalFillers where !removed.contains(word) {
            result.append((word: word, isCustom: false, isContextDependent: false))
        }

        for word in FillerWordList.contextDependentFillers where !removed.contains(word) {
            result.append((word: word, isCustom: false, isContextDependent: true))
        }

        for word in customFillerWords {
            result.append((word: word, isCustom: true, isContextDependent: false))
        }

        for word in customContextFillerWords {
            result.append((word: word, isCustom: true, isContextDependent: true))
        }

        return result.sorted { $0.word < $1.word }
    }

    var hasFillerCustomizations: Bool {
        !customFillerWords.isEmpty || !customContextFillerWords.isEmpty || !removedDefaultFillers.isEmpty
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
                let newSettings = UserSettings()
                context.insert(newSettings)
                try context.save()
                settings = newSettings
                syncLocalState()
            }
        } catch {
            logger.error("Error loading settings: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
    
    private func syncLocalState() {
        guard let settings else { return }

        isSyncing = true
        defer { isSyncing = false }

        userName = settings.userName
        defaultDuration = RecordingDuration(rawValue: settings.defaultDuration) ?? .sixty
        dailyReminderEnabled = settings.dailyReminderEnabled

        var components = DateComponents()
        components.hour = settings.dailyReminderHour
        components.minute = settings.dailyReminderMinute
        reminderTime = Calendar.current.date(from: components) ?? Date()

        weeklyGoalSessions = settings.weeklyGoalSessions

        trackPauses = settings.trackPauses
        trackFillerWords = settings.trackFillerWords
        targetWPM = settings.targetWPM
        autoPaceTarget = settings.autoPaceTarget

        hideAnsweredPrompts = settings.hideAnsweredPrompts
        enabledPromptCategories = Set(settings.enabledCategories)
        storyPracticeEnabled = settings.storyPracticeEnabled

        vocabChallengeEnabled = settings.vocabChallengeEnabled
        vocabChallengeWordCount = settings.vocabChallengeWordCount
        vocabChallengeIntroduceNew = settings.vocabChallengeIntroduceNew
        vocabChallengeLevelOverride = settings.vocabChallengeLevelOverride

        speakerLevel = settings.resolvedSpeakerLevel

        countdownDuration = CountdownDuration(rawValue: settings.countdownDuration) ?? .fifteen
        countdownStyle = CountdownStyle(rawValue: settings.countdownStyle) ?? .countDown

        timerEndBehavior = TimerEndBehavior(rawValue: settings.timerEndBehavior) ?? .saveAndStop

        waveformStyle = WaveformStyle(rawValue: settings.waveformStyle) ?? .rings
        recordButtonStyle = RecordButtonStyle(rawValue: settings.recordButtonStyle) ?? .classic
        countdownLook = TimerLook(rawValue: settings.countdownLook) ?? .ring
        recordingBackdrop = RecordingBackdrop(rawValue: settings.countdownBackdrop) ?? .base

        glassAppearance = GlassAppearance(rawValue: settings.glassAppearance) ?? .light
        appCanvas = AppCanvas(rawValue: settings.appCanvas) ?? .classic

        soundPack = SoundPack(rawValue: settings.soundPack) ?? .soft
        ChirpPlayer.shared.pack = soundPack

        vocabWords = settings.vocabWords
        dictationBiasWords = settings.dictationBiasWords

        customFillerWords = settings.customFillerWords
        customContextFillerWords = settings.customContextFillerWords
        removedDefaultFillers = settings.removedDefaultFillers

        hapticCoachingEnabled = settings.hapticCoachingEnabled

        chirpSoundEnabled = settings.chirpSoundEnabled
        ChirpPlayer.shared.isEnabled = settings.chirpSoundEnabled

        sessionFeedbackEnabled = settings.sessionFeedbackEnabled
        customFeedbackQuestions = settings.customFeedbackQuestions

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

        settings.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultDuration = defaultDuration.rawValue
        settings.dailyReminderEnabled = dailyReminderEnabled
        
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        settings.dailyReminderHour = components.hour ?? 9
        settings.dailyReminderMinute = components.minute ?? 0
        
        settings.weeklyGoalSessions = weeklyGoalSessions

        settings.trackPauses = trackPauses
        settings.trackFillerWords = trackFillerWords
        settings.targetWPM = targetWPM
        settings.autoPaceTarget = autoPaceTarget
        
        settings.hideAnsweredPrompts = hideAnsweredPrompts
        settings.enabledPromptCategories = enabledPromptCategories.map { $0.rawValue }
        settings.storyPracticeEnabled = storyPracticeEnabled

        settings.vocabChallengeEnabled = vocabChallengeEnabled
        settings.vocabChallengeWordCount = min(3, max(1, vocabChallengeWordCount))
        settings.vocabChallengeLevelOverride = min(3, max(0, vocabChallengeLevelOverride))
        // ponytail: sources and spacing are no longer knobs — the picker keeps
        // the flags so it stays testable, the UI just never turns them off.
        settings.vocabChallengeUseBank = true
        settings.vocabChallengeUseDictionary = true
        settings.vocabChallengeIntroduceNew = vocabChallengeIntroduceNew
        settings.vocabChallengeSpacedReview = true

        settings.speakerLevel = speakerLevel.rawValue

        settings.countdownDuration = countdownDuration.rawValue
        settings.countdownStyle = countdownStyle.rawValue

        settings.timerEndBehavior = timerEndBehavior.rawValue

        settings.waveformStyle = waveformStyle.rawValue
        settings.recordButtonStyle = recordButtonStyle.rawValue
        settings.countdownLook = countdownLook.rawValue
        settings.countdownBackdrop = recordingBackdrop.rawValue

        settings.glassAppearance = glassAppearance.rawValue
        settings.appCanvas = appCanvas.rawValue

        settings.soundPack = soundPack.rawValue
        ChirpPlayer.shared.pack = soundPack

        settings.vocabWords = vocabWords
        settings.dictationBiasWords = dictationBiasWords

        settings.customFillerWords = customFillerWords
        settings.customContextFillerWords = customContextFillerWords
        settings.removedDefaultFillers = removedDefaultFillers

        settings.hapticCoachingEnabled = hapticCoachingEnabled

        settings.chirpSoundEnabled = chirpSoundEnabled
        ChirpPlayer.shared.isEnabled = chirpSoundEnabled

        settings.sessionFeedbackEnabled = sessionFeedbackEnabled
        settings.customFeedbackQuestions = customFeedbackQuestions

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
            
            if dailyReminderEnabled {
                await scheduleReminderNotification()
            } else {
                await cancelReminderNotification()
            }
        } catch {
            logger.error("Error saving settings: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }
    
    @MainActor
    func commitUserName() async {
        userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        await saveSettings()
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
            showVocabError("That's a filler word, we track those separately")
            return
        }
        guard trimmed.count >= 2 else {
            showVocabError("Use at least 2 characters")
            return
        }
        if WordSafety.isBlocked(trimmed) {
            showVocabError("That word isn't allowed")
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
    func removeVocabWord(_ word: String) {
        vocabWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        Task { await saveSettings() }
    }

    /// Bulk-add vocab words from dictation, skipping duplicates and fillers.
    /// Returns the count of words actually added.
    @MainActor
    @discardableResult
    func addVocabWords(_ words: [String]) -> Int {
        var added = 0
        for raw in words {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2,
                  WordSafety.allows(trimmed),
                  !vocabWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }),
                  !isFillerWord(trimmed) else { continue }
            vocabWords.append(trimmed)
            added += 1
        }
        if added > 0 {
            Haptics.success()
            Task { await saveSettings() }
        }
        return added
    }

    /// Bulk-add dictation bias words from dictation, skipping duplicates and fillers.
    /// Returns the count of words actually added.
    @MainActor
    @discardableResult
    func addDictationBiasWords(_ words: [String]) -> Int {
        var added = 0
        for raw in words {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2,
                  WordSafety.allows(trimmed),
                  !dictationBiasWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }),
                  !isFillerWord(trimmed) else { continue }
            dictationBiasWords.append(trimmed)
            added += 1
        }
        if added > 0 {
            Haptics.success()
            Task { await saveSettings() }
        }
        return added
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
        if WordSafety.isBlocked(trimmed) {
            showDictationError("That word isn't allowed")
            return
        }
        guard !dictationBiasWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            showDictationError("Already in your dictation dictionary")
            return
        }
        guard !isFillerWord(trimmed) else {
            showDictationError("That's a filler word, avoid biasing it")
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
        if FillerWordList.unconditionalFillers.contains(trimmed) || FillerWordList.contextDependentFillers.contains(trimmed) {
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

        settings.defaultDuration = 60
        settings.dailyReminderEnabled = false
        settings.dailyReminderHour = 9
        settings.dailyReminderMinute = 0
        settings.weeklyGoalSessions = 5
        settings.trackPauses = true
        settings.trackFillerWords = true
        settings.targetWPM = 150
        settings.autoPaceTarget = true
        settings.calibratedWPM = nil
        settings.hideAnsweredPrompts = true
        settings.enabledPromptCategories = PromptCategory.allCases.map { $0.rawValue }
        settings.countdownDuration = 15
        settings.countdownStyle = 0
        settings.timerEndBehavior = 0
        settings.waveformStyle = 0
        settings.recordButtonStyle = 0
        settings.countdownLook = 0
        settings.countdownBackdrop = 0
        settings.glassAppearance = 0
        settings.appCanvas = 0
        settings.soundPack = 0
        settings.shareCardTheme = 0
        ChirpPlayer.shared.pack = .soft
        settings.vocabWords = []
        settings.dictationBiasWords = []
        settings.vocabChallengeEnabled = true
        settings.vocabChallengeWordCount = 2
        settings.vocabChallengeLevelOverride = 0
        settings.vocabChallengeUseBank = true
        settings.vocabChallengeUseDictionary = true
        settings.vocabChallengeIntroduceNew = true
        settings.vocabChallengeSpacedReview = true
        settings.customFillerWords = []
        settings.customContextFillerWords = []
        settings.removedDefaultFillers = []
        settings.chirpSoundEnabled = true
        settings.sessionFeedbackEnabled = false
        settings.customFeedbackQuestions = []

        settings.voiceProfileF0Hz = nil
        settings.voiceProfileEnergyDb = nil
        settings.voiceProfileSampleCount = 0
        settings.voiceProfileLastUpdated = nil

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
            logger.error("Error resetting settings: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    @MainActor
    func clearAllData() async {
        guard let context = modelContext else { return }

        do {
            let recordingDescriptor = FetchDescriptor<Recording>()
            let recordings = try context.fetch(recordingDescriptor)
            for recording in recordings {
                if let audioURL = recording.resolvedAudioURL {
                    ICloudStorageService.shared.removeFile(at: audioURL)
                }
                if let videoURL = recording.resolvedVideoURL {
                    ICloudStorageService.shared.removeFile(at: videoURL)
                }
                context.delete(recording)
            }

            let goalDescriptor = FetchDescriptor<UserGoal>()
            let goals = try context.fetch(goalDescriptor)
            for goal in goals {
                context.delete(goal)
            }

            let achievementDescriptor = FetchDescriptor<Achievement>()
            let achievements = try context.fetch(achievementDescriptor)
            for achievement in achievements {
                context.delete(achievement)
            }

            let curriculumDescriptor = FetchDescriptor<CurriculumProgress>()
            let curriculumItems = try context.fetch(curriculumDescriptor)
            for item in curriculumItems {
                context.delete(item)
            }

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

            // The FAQ calls this a full data reset, so it has to include the
            // usage log. It lives in a file rather than the store, so deleting
            // rows never touched it.
            AnalyticsService.shared.reset()
        } catch {
            logger.error("Error clearing data: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    @MainActor
    func saveVocabChallengeSettings() {
        Task { await saveSettings() }
    }

    // MARK: - Pace Target

    var displayTargetWPM: Int {
        settings.resolvedTargetWPM
    }

    var hasCalibratedWPM: Bool {
        settings?.calibratedWPM != nil
    }

    // MARK: - Voice Profile

    var voiceProfileSampleCount: Int {
        settings?.voiceProfileSampleCount ?? 0
    }

    var voiceProfileLastUpdated: Date? {
        settings?.voiceProfileLastUpdated
    }

    @MainActor
    func resetVoiceProfile() {
        guard let settings, let context = modelContext else { return }
        settings.voiceProfileF0Hz = nil
        settings.voiceProfileEnergyDb = nil
        settings.voiceProfileSampleCount = 0
        settings.voiceProfileLastUpdated = nil
        try? context.save()
    }

    @MainActor
    func saveCalibrationProfile(_ profile: VoiceProfile) {
        guard let settings, let context = modelContext else { return }
        settings.voiceProfileF0Hz = profile.f0Hz
        settings.voiceProfileEnergyDb = profile.energyDb
        settings.voiceProfileSampleCount = max(settings.voiceProfileSampleCount, 3)
        settings.voiceProfileLastUpdated = Date()
        try? context.save()
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

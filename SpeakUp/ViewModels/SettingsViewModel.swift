import Foundation
import SwiftUI
import SwiftData

@Observable
class SettingsViewModel {
    var settings: UserSettings?
    var isLoading = true
    var showingResetConfirmation = false
    var showingClearDataConfirmation = false
    
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
    
    // Local state - Prompt Settings
    var showDailyPrompt: Bool = true
    var enabledPromptCategories: Set<PromptCategory> = Set(PromptCategory.allCases)

    // Local state - Countdown
    var countdownDuration: CountdownDuration = .fifteen

    private var modelContext: ModelContext?
    private let notificationService = NotificationService()
    
    func configure(with context: ModelContext) {
        self.modelContext = context
        Task { @MainActor in
            await loadSettings()
        }
    }
    
    @MainActor
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
        
        // Prompt settings
        showDailyPrompt = settings.showDailyPrompt
        enabledPromptCategories = Set(settings.enabledCategories)

        // Countdown duration
        countdownDuration = CountdownDuration(rawValue: settings.countdownDuration) ?? .fifteen
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
        
        // Prompt settings
        settings.showDailyPrompt = showDailyPrompt
        settings.enabledPromptCategories = enabledPromptCategories.map { $0.rawValue }

        // Countdown duration
        settings.countdownDuration = countdownDuration.rawValue

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
        settings.showDailyPrompt = true
        settings.enabledPromptCategories = PromptCategory.allCases.map { $0.rawValue }
        settings.countdownDuration = 15

        do {
            try context.save()
            syncLocalState()
        } catch {
            print("Error resetting settings: \(error)")
        }
    }
    
    @MainActor
    func clearAllData() async {
        guard let context = modelContext else { return }
        
        do {
            // Delete all recordings
            let recordingDescriptor = FetchDescriptor<Recording>()
            let recordings = try context.fetch(recordingDescriptor)
            for recording in recordings {
                // Delete files
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

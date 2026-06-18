import Foundation
import SwiftUI
import AVFoundation
import Speech
import UserNotifications
import UIKit

// MARK: - Step Machine

/// Ordered steps in the redesigned interactive onboarding. Each step owns its
/// own dedicated view and inline action (no pinned button bar). Steps that the
/// user has already addressed in a previous launch are skippable on resume.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case toolkit
    case name
    case goal
    case level
    case vocab
    case mic
    case reminder
    case ready

    var id: Int { rawValue }

    /// Whether the user can navigate back from this step. The terminal
    /// `ready` step is one-way — once they hit it, they're done.
    var allowsBack: Bool {
        switch self {
        case .welcome, .ready: return false
        default: return true
        }
    }
}

// MARK: - Result

/// Final picks the user makes during onboarding. Returned to `ContentView`
/// so it can apply them to the persisted `UserSettings` row in one shot.
struct OnboardingResult {
    let userName: String
    let goal: OnboardingGoal
    let speakerLevel: SpeakerLevel
    let vocabWords: [String]
    let dictionaryWords: [String]
    let reminderEnabled: Bool
    let reminderHour: Int
    let reminderMinute: Int
    let launchFirstRecording: Bool
}

// MARK: - View Model

@Observable
@MainActor
final class OnboardingViewModel {
    // State machine
    var currentStep: OnboardingStep = .welcome

    // Identity
    var nameInput: String = ""

    // Practice intent
    var selectedGoal: OnboardingGoal? = nil
    var speakerLevel: SpeakerLevel = .intermediate

    // Mic permission + live test
    var hasMicPermission = false
    var isRequestingMicPermission = false
    var micLevel: Float = 0  // 0–1, smoothed for waveform
    var hasHeardVoice = false
    private let audioService = AudioService()
    private var levelMonitorTask: Task<Void, Never>? = nil

    // Speech recognition permission. Requested alongside the mic so the
    // Apple Speech fallback transcriber (used when WhisperKit is unavailable
    // or recovering) is pre-authorized. Denial is non-blocking — WhisperKit
    // remains the primary transcriber and does not require this permission.
    var hasSpeechPermission = false

    // Notification permission + reminder time
    var hasNotificationPermission = false
    var isRequestingNotificationPermission = false
    var reminderEnabled = true
    var reminderTime: Date = OnboardingViewModel.defaultReminderTime()

    // Vocab + dictionary seeds (still populated; surfaced on the ready step
    // as a quick preview rather than a full editing page).
    var vocabWords: [String] = OnboardingViewModel.vocabSeeds(for: .intermediate)
    var dictionaryWords: [String] = []

    // Final action
    var launchFirstRecording = true

    static func vocabSeeds(for level: SpeakerLevel) -> [String] {
        switch level {
        case .beginner:
            return ["Confident", "Practice", "Improve", "Prepare",
                    "Express", "Focus", "Listen", "Engage"]
        case .intermediate:
            return ["Strategic", "Authentic", "Resilient", "Empathetic",
                    "Decisive", "Adaptable", "Articulate", "Visionary"]
        case .advanced:
            return ["Compelling", "Nuanced", "Cogent", "Eloquent",
                    "Transformative", "Substantive", "Incisive", "Persuasive"]
        }
    }

    // v3 keys: invalidate older saved state because vocab moved after level
    // (rawValues changed), which would otherwise restore to the wrong page.
    private static let resumeStepKey = "onboarding.lastReachedStep.v3"
    private static let resumeNameKey = "onboarding.draftName.v3"
    private static let resumeGoalKey = "onboarding.draftGoal.v3"
    private static let resumeLevelKey = "onboarding.draftLevel.v3"

    // MARK: Lifecycle

    nonisolated init() {}

    // MARK: Computed

    var trimmedName: String {
        nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canAdvanceFromName: Bool { !trimmedName.isEmpty }

    /// Bar fill progresses linearly across all steps. Even welcome shows a
    /// sliver of fill so the bar never reads as "empty" at first launch.
    var stepProgress: Double {
        let total = max(1, OnboardingStep.allCases.count)
        return Double(currentStep.rawValue + 1) / Double(total)
    }

    // MARK: Persistence

    /// Restore any in-flight progress from a prior launch (force quit, crash,
    /// or just re-opening before completion). Stored in UserDefaults so the
    /// drafts survive without touching the SwiftData store.
    func restoreFromDefaults() {
        let defaults = UserDefaults.standard
        if let raw = defaults.object(forKey: Self.resumeStepKey) as? Int,
           let step = OnboardingStep(rawValue: raw) {
            currentStep = step
        }
        if let savedName = defaults.string(forKey: Self.resumeNameKey) {
            nameInput = savedName
        }
        if let goalRaw = defaults.object(forKey: Self.resumeGoalKey) as? Int,
           let goal = OnboardingGoal(rawValue: goalRaw) {
            selectedGoal = goal
        }
        if let levelRaw = defaults.object(forKey: Self.resumeLevelKey) as? Int,
           let level = SpeakerLevel(rawValue: levelRaw) {
            speakerLevel = level
            vocabWords = Self.vocabSeeds(for: level)
        }
    }

    private func persistProgress() {
        let defaults = UserDefaults.standard
        defaults.set(currentStep.rawValue, forKey: Self.resumeStepKey)
        defaults.set(trimmedName, forKey: Self.resumeNameKey)
        if let goal = selectedGoal {
            defaults.set(goal.rawValue, forKey: Self.resumeGoalKey)
        }
        defaults.set(speakerLevel.rawValue, forKey: Self.resumeLevelKey)
    }

    /// Wipes draft state once onboarding has been applied. Called by
    /// `ContentView` after `applyOnboardingResult` succeeds.
    static func clearResumeState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: resumeStepKey)
        defaults.removeObject(forKey: resumeNameKey)
        defaults.removeObject(forKey: resumeGoalKey)
        defaults.removeObject(forKey: resumeLevelKey)
    }

    // MARK: Step Navigation

    func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        Haptics.medium()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            currentStep = next
        }
        persistProgress()
    }

    func goBack() {
        guard currentStep.allowsBack,
              let previous = OnboardingStep(rawValue: currentStep.rawValue - 1)
        else { return }
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentStep = previous
        }
        persistProgress()
    }

    func selectGoal(_ goal: OnboardingGoal) {
        Haptics.selection()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedGoal = goal
        }
        persistProgress()
    }

    func selectLevel(_ level: SpeakerLevel) {
        Haptics.selection()
        let oldSeeds = Self.vocabSeeds(for: speakerLevel)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            speakerLevel = level
        }
        if vocabWords == oldSeeds {
            vocabWords = Self.vocabSeeds(for: level)
        }
        persistProgress()
    }

    // MARK: Mic Permission + Live Test

    func checkMicPermission() {
        hasMicPermission = AVAudioApplication.shared.recordPermission == .granted
        audioService.hasPermission = hasMicPermission
        hasSpeechPermission = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestMicAndStartTest() async {
        if !hasMicPermission {
            isRequestingMicPermission = true
            let granted = await audioService.requestPermission()
            isRequestingMicPermission = false
            hasMicPermission = granted
            guard granted else { return }
            Haptics.success()
        }
        // Chain the speech recognition prompt right after mic. Pre-authorising
        // here avoids a second system prompt the first time the Apple Speech
        // fallback transcriber kicks in. Denial is intentionally non-fatal.
        if !hasSpeechPermission {
            await requestSpeechPermission()
        }
        await startMicTest()
    }

    private func requestSpeechPermission() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        hasSpeechPermission = status == .authorized
    }

    /// Re-enter the mic test if the user already granted permission. Idempotent
    /// — safe to call every time the mic step appears. No-op when permission
    /// hasn't been granted yet (the user must tap "Enable microphone" first).
    func resumeMicTestIfPermitted() async {
        guard hasMicPermission, levelMonitorTask == nil else { return }
        await startMicTest()
    }

    private func startMicTest() async {
        // Kick off a short throwaway recording so we can pull live meter
        // values. The file is deleted as soon as we stop the test.
        do {
            _ = try await audioService.startRecording()
        } catch {
            print("Onboarding mic test failed to start: \(error)")
            return
        }
        levelMonitorTask?.cancel()
        levelMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let dbfs = self.audioService.getAudioLevel()
                // Map -60dB → 0, 0dB → 1 with a gentle ease.
                let normalized = max(0, min(1, (Double(dbfs) + 60) / 60))
                let smoothed = Float(pow(normalized, 0.7))
                await MainActor.run {
                    self.micLevel = smoothed
                    if smoothed > 0.18, !self.hasHeardVoice {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            self.hasHeardVoice = true
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    func stopMicTest() {
        levelMonitorTask?.cancel()
        levelMonitorTask = nil
        audioService.cancelRecording()
        micLevel = 0
    }

    // MARK: Notification Permission

    func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        hasNotificationPermission = settings.authorizationStatus == .authorized
    }

    func requestNotificationPermission() async {
        isRequestingNotificationPermission = true
        defer { isRequestingNotificationPermission = false }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            hasNotificationPermission = granted
            reminderEnabled = granted ? reminderEnabled : false
            if granted { Haptics.success() }
        } catch {
            print("Notification permission error: \(error)")
        }
    }

    // MARK: Result

    func makeResult() -> OnboardingResult {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        // Always commit the current name into the dictation dictionary at
        // result time so renaming after the name step (back-nav, edit on a
        // later page) doesn't leave the dictionary out of sync.
        var finalDictionary = dictionaryWords
        if !trimmedName.isEmpty,
           !finalDictionary.contains(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            finalDictionary.append(trimmedName)
        }
        return OnboardingResult(
            userName: trimmedName,
            goal: selectedGoal ?? .everydayConfidence,
            speakerLevel: speakerLevel,
            vocabWords: vocabWords,
            dictionaryWords: finalDictionary,
            reminderEnabled: reminderEnabled && hasNotificationPermission,
            reminderHour: comps.hour ?? 9,
            reminderMinute: comps.minute ?? 0,
            launchFirstRecording: launchFirstRecording
        )
    }

    // MARK: Word Bank Editing

    /// Spell-checker reused across add attempts. `UITextChecker` is cheap to
    /// construct but caching avoids re-allocating on every keystroke commit.
    private static let spellChecker = UITextChecker()

    /// Append a vocab word after validation. Returns `true` on success so the
    /// caller can decide whether to clear its input field. Failures fire an
    /// error haptic so the user gets immediate tactile feedback that the
    /// word was rejected.
    @discardableResult
    func addVocabWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidVocabWord(trimmed) else {
            Haptics.error()
            return false
        }
        guard !vocabWords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            Haptics.error()
            return false
        }
        Haptics.light()
        vocabWords.append(trimmed)
        return true
    }

    /// Validate a candidate vocab entry. Word must be at least 2 characters,
    /// purely alphabetic, and recognised by `UITextChecker` against US English.
    private func isValidVocabWord(_ word: String) -> Bool {
        guard word.count >= 2 else { return false }
        guard word.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return false }
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = Self.spellChecker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en_US"
        )
        return misspelled.location == NSNotFound
    }

    func removeVocabWord(_ word: String) {
        Haptics.light()
        vocabWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    private static func defaultReminderTime() -> Date {
        var comps = DateComponents()
        comps.hour = 9
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}

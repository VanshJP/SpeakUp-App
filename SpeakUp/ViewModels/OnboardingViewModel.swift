import Foundation
import SwiftUI
import AVFoundation
import Speech
import UserNotifications
import UIKit

// MARK: - Step Machine

/// Ordered steps in the interactive onboarding. Each step owns its own
/// dedicated view and inline action (no pinned button bar). Steps that the
/// user has already addressed in a previous launch are skippable on resume.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case howItWorks
    case whatsInside
    case name
    case goal
    case level
    case vocab
    case mic
    case calibrate
    case intelligence
    case reminder
    case ready

    var id: Int { rawValue }

    /// Whether the user can navigate back from this step. The terminal
    /// `ready` step is one-way: once they hit it, they're done.
    var allowsBack: Bool {
        switch self {
        case .welcome, .ready: return false
        default: return true
        }
    }

    /// Hero steps run their own full-bleed layout instead of the shared
    /// `OnboardingPage` scaffold, and carry no step counter.
    var isHero: Bool {
        self == .welcome || self == .ready
    }

    /// Steps that put a labelled decline action in their own footer
    /// ("Skip and learn it as I record", "Not now"). The global Skip in the top
    /// bar would be a second, vaguer copy of the same escape hatch.
    var providesOwnSkip: Bool {
        switch self {
        case .calibrate, .intelligence, .reminder: return true
        default: return false
        }
    }

    /// Steps a first run walks before the first recording.
    ///
    /// Calibration, the on-device model download, and the reminder prompt are
    /// deliberately absent. Each one asks for effort, storage, or a system
    /// permission before the user has seen a single score, and the score is the
    /// only thing that has earned any of it. All three are offered again on
    /// `FirstRecordingSetupSheet`, immediately after the first session.
    static let firstRunSteps: [OnboardingStep] = [
        .welcome, .howItWorks, .whatsInside, .name, .goal, .level, .vocab, .mic, .ready
    ]

    /// Steps moved out of the first run and offered after the first result.
    static let deferredSteps: [OnboardingStep] = [.calibrate, .intelligence, .reminder]

    /// Stable name for the drop-off funnel. Deliberately not derived from any
    /// on-screen copy: reworded headlines must not split one step into two
    /// series and make the funnel look like a cliff that isn't there.
    var analyticsName: String {
        switch self {
        case .welcome: return "welcome"
        case .howItWorks: return "how_it_works"
        case .whatsInside: return "whats_inside"
        case .name: return "name"
        case .goal: return "goal"
        case .level: return "level"
        case .vocab: return "vocab"
        case .mic: return "mic"
        case .calibrate: return "calibrate"
        case .intelligence: return "intelligence"
        case .reminder: return "reminder"
        case .ready: return "ready"
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
    /// Baseline voice signature captured on the calibration step. Nil when the
    /// user skipped it, in which case the profile is learned from recordings.
    let voiceProfile: VoiceProfile?
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

    // Voice calibration. The calibration sheet reuses `VoiceCalibrationView`,
    // which returns the extracted profile; onboarding holds it until the
    // result is applied to `UserSettings` so a cancelled flow writes nothing.
    var voiceProfile: VoiceProfile?
    var showingCalibration = false

    var hasCalibratedVoice: Bool { voiceProfile != nil }

    // Speech recognition permission. Requested alongside the mic so the
    // Apple Speech fallback transcriber (used when WhisperKit is unavailable
    // or recovering) is pre-authorized. Denial is non-blocking, since WhisperKit
    // remains the primary transcriber and does not require this permission.
    var hasSpeechPermission = false

    // Notification permission + reminder time
    var hasNotificationPermission = false
    var isRequestingNotificationPermission = false
    /// Off until the user asks for it. The reminder step is no longer part of
    /// the first run, so defaulting this on would fire a notification
    /// permission prompt nobody agreed to.
    var reminderEnabled = false
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

    // v6 keys: calibration, the model download, and reminders left the first
    // run, so a v5 resume could land on a step this flow no longer walks.
    // Bumping invalidates that saved state, the same reason v5 existed.
    private static let resumeStepKey = "onboarding.lastReachedStep.v6"
    private static let resumeNameKey = "onboarding.draftName.v6"
    private static let resumeGoalKey = "onboarding.draftGoal.v6"
    private static let resumeLevelKey = "onboarding.draftLevel.v6"

    // MARK: Lifecycle

    nonisolated init() {}

    // MARK: Computed

    var trimmedName: String {
        nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canAdvanceFromName: Bool { !trimmedName.isEmpty }

    /// The flow this run walks. Navigation indexes into this rather than
    /// walking `rawValue + 1`, so deferring a step is a change to one array.
    var steps: [OnboardingStep] { OnboardingStep.firstRunSteps }

    /// The steps that carry a counter and a tick. The hero cover and the
    /// terminal recap bookend the flow rather than being part of it. Counting
    /// them meant the user never saw the last number ("Step 10 of 11" was the
    /// highest label the flow could ever show).
    private var countedSteps: [OnboardingStep] { steps.filter { !$0.isHero } }

    var stepCount: Int { max(1, countedSteps.count) }

    private var countedIndex: Int? {
        countedSteps.firstIndex(of: currentStep)
    }

    /// Ticks fill across the counted steps only. The terminal step reads full.
    var stepProgress: Double {
        if currentStep == .ready { return 1 }
        guard let index = countedIndex else { return 0 }
        return Double(index + 1) / Double(stepCount)
    }

    /// Small-caps counter shown above each page title. Hero steps opt out.
    var stepCounterLabel: String? {
        guard let index = countedIndex else { return nil }
        return "Step \(index + 1) of \(stepCount)"
    }

    // MARK: Persistence

    /// Restore any in-flight progress from a prior launch (force quit, crash,
    /// or just re-opening before completion). Stored in UserDefaults so the
    /// drafts survive without touching the SwiftData store.
    func restoreFromDefaults() {
        let defaults = UserDefaults.standard
        if let raw = defaults.object(forKey: Self.resumeStepKey) as? Int,
           let step = OnboardingStep(rawValue: raw),
           steps.contains(step) {
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

    // Note: none of these wrap their mutation in `withAnimation`. The views own
    // the motion through `.motion(_:value:)`, which is the only path that goes
    // still under Reduce Motion. A `withAnimation` here animated regardless,
    // and fought the view-level curve for the same state change.

    func advance() {
        move(by: 1, action: "continue")
    }

    /// Leaving a step without doing what it asked. Separate from `advance` so
    /// the funnel can tell "answered and moved on" from "escaped" — a step
    /// everyone skips is a step that should not be in the first run.
    func skip() {
        move(by: 1, action: "skip")
    }

    func goBack() {
        guard currentStep.allowsBack else { return }
        move(by: -1, action: "back")
    }

    private func move(by offset: Int, action: String) {
        guard let index = steps.firstIndex(of: currentStep) else { return }
        let target = index + offset
        guard steps.indices.contains(target) else { return }

        AnalyticsService.shared.log(.onboardingStep(currentStep.analyticsName, action: action))
        if offset > 0 { Haptics.medium() } else { Haptics.light() }
        currentStep = steps[target]
        persistProgress()
    }

    func selectGoal(_ goal: OnboardingGoal) {
        Haptics.selection()
        selectedGoal = goal
        persistProgress()
    }

    /// `haptic: false` is used by the level `SectionPicker`, which already
    /// fires its own selection haptic before writing through the binding.
    func selectLevel(_ level: SpeakerLevel, haptic: Bool = true) {
        if haptic { Haptics.selection() }
        let oldSeeds = Self.vocabSeeds(for: speakerLevel)
        speakerLevel = level
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
        await requestMicPermissionOnly()
        guard hasMicPermission else { return }
        await startMicTest()
    }

    /// Mic + speech authorization without arming the live meter. Used by the
    /// calibration step, which needs permission but drives its own recording
    /// through `VoiceCalibrationView`.
    func requestMicPermissionOnly() async {
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
    }

    private func requestSpeechPermission() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        hasSpeechPermission = status == .authorized
    }

    /// Re-enter the mic test if the user already granted permission. Idempotent,
    /// so safe to call every time the mic step appears. No-op when permission
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
                self.micLevel = smoothed
                if smoothed > 0.18, !self.hasHeardVoice {
                    self.hasHeardVoice = true
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

    // MARK: Voice Calibration

    func startCalibration() {
        Haptics.medium()
        showingCalibration = true
    }

    /// Stores the baseline profile returned by `VoiceCalibrationView`. Written
    /// to `UserSettings` only once onboarding completes.
    func applyCalibration(_ profile: VoiceProfile) {
        voiceProfile = profile
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
        AnalyticsService.shared.log(.onboardingStep(currentStep.analyticsName, action: "complete"))
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
            launchFirstRecording: launchFirstRecording,
            voiceProfile: voiceProfile
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

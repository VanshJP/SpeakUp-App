import Foundation
import os.log
import SwiftUI
import AVFoundation
import Speech
import UserNotifications
import UIKit

// MARK: - Step Machine

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case name
    case goal
    case level
    case mic
    case baselineBriefing
    case baseline
    case calibrate
    case intelligence
    case reminder

    var id: Int { rawValue }

    var allowsBack: Bool {
        switch self {
        case .welcome, .baseline: return false
        default: return true
        }
    }

    var isHero: Bool {
        switch self {
        case .welcome, .baselineBriefing, .baseline: return true
        default: return false
        }
    }

    var providesOwnSkip: Bool {
        switch self {
        case .calibrate, .intelligence, .reminder: return true
        default: return false
        }
    }

    /// Steps a first run walks. The flow ends inside the baseline recording —
    /// the first guided take, its analysis, and its reveal — rather than
    /// handing the user off to an unguided recorder after a recap screen.
    static let firstRunSteps: [OnboardingStep] = [
        .welcome, .name, .goal, .level, .mic, .baselineBriefing, .baseline
    ]

    /// Stable name for the drop-off funnel. Deliberately not derived from any
    /// on-screen copy: reworded headlines must not split one step into two
    /// series and make the funnel look like a cliff that isn't there.
    var analyticsName: String {
        switch self {
        case .welcome: return "welcome"
        case .name: return "name"
        case .goal: return "goal"
        case .level: return "level"
        case .mic: return "mic"
        case .baselineBriefing: return "baseline_briefing"
        case .baseline: return "baseline"
        case .calibrate: return "calibrate"
        case .intelligence: return "intelligence"
        case .reminder: return "reminder"
        }
    }
}

// MARK: - Result

struct OnboardingResult {
    let userName: String
    let goals: [OnboardingGoal]
    let speakerLevel: SpeakerLevel
    let vocabWords: [String]
    let dictionaryWords: [String]
    let reminderEnabled: Bool
    let reminderHour: Int
    let reminderMinute: Int
    let baselineRecordingID: UUID?
    let reviewBaselineOnFinish: Bool
    let voiceProfile: VoiceProfile?
}

// MARK: - View Model

@Observable
@MainActor
final class OnboardingViewModel {
    private let logger = Logger.app("Onboarding")
    var currentStep: OnboardingStep = .welcome

    var nameInput: String = ""

    var selectedGoals: [OnboardingGoal] = []
    static let maxGoals = 3
    var speakerLevel: SpeakerLevel = .intermediate
    var hasPickedLevel = false

    var hasMicPermission = false
    var isRequestingMicPermission = false
    var micLevel: Float = 0  // 0–1, smoothed for waveform
    var hasHeardVoice = false
    private let audioService = AudioService()
    private var levelMonitorTask: Task<Void, Never>? = nil

    var voiceProfile: VoiceProfile?
    var showingCalibration = false

    var hasCalibratedVoice: Bool { voiceProfile != nil }

    var hasSpeechPermission = false

    var hasNotificationPermission = false
    var isRequestingNotificationPermission = false
    var reminderEnabled = false
    var reminderTime: Date = OnboardingViewModel.defaultReminderTime()

    var vocabWords: [String] = OnboardingViewModel.vocabSeeds(for: .intermediate)
    var dictionaryWords: [String] = []

    // MARK: Baseline take

    /// The guided first take. `ready → countdown → recording`; everything after
    /// stop (persist, analyze, reveal) is view-owned because it needs the
    /// model context.
    enum BaselinePhase {
        case ready, countdown, recording, saving
    }

    var baselinePhase: BaselinePhase = .ready
    var baselineCountdownValue = 3
    var baselineElapsed: Int = 0
    var baselineNote: String?
    private var baselineCountdownTask: Task<Void, Never>?
    private var baselineLevelSamples: [Float] = []
    private var baselineSampleCounter = 0

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

    private static let resumeStepKey = "onboarding.lastReachedStep.v8"
    private static let resumeNameKey = "onboarding.draftName.v8"
    private static let resumeGoalsKey = "onboarding.draftGoals.v8"
    private static let resumeLevelKey = "onboarding.draftLevel.v8"

    // MARK: Lifecycle

    nonisolated init() {}

    // MARK: Computed

    var trimmedName: String {
        nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canAdvanceFromName: Bool { !trimmedName.isEmpty }

    /// At the cap, unpicked goals stop responding — `toggleGoal` refuses and
    /// the step dims them, rather than silently dropping an earlier pick.
    var hasReachedGoalLimit: Bool { selectedGoals.count >= Self.maxGoals }

    /// The flow this run walks. Navigation indexes into this rather than
    /// walking `rawValue + 1`, so deferring a step is a change to one array.
    var steps: [OnboardingStep] { OnboardingStep.firstRunSteps }

    private var countedSteps: [OnboardingStep] { steps.filter { !$0.isHero } }

    var stepCount: Int { max(1, countedSteps.count) }

    private var countedIndex: Int? {
        countedSteps.firstIndex(of: currentStep)
    }

    /// Ticks fill across the counted steps only. The baseline beats read full
    /// (the meter is hidden there, but Back into a counted step must not
    /// animate from zero).
    var stepProgress: Double {
        if currentStep == .baselineBriefing || currentStep == .baseline { return 1 }
        guard let index = countedIndex else { return 0 }
        return Double(index + 1) / Double(stepCount)
    }

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
            // Never resume cold onto the live recorder — the briefing carries
            // the context that makes the recorder make sense.
            currentStep = step == .baseline ? .baselineBriefing : step
        }
        if let savedName = defaults.string(forKey: Self.resumeNameKey) {
            nameInput = savedName
        }
        if let goalRaws = defaults.array(forKey: Self.resumeGoalsKey) as? [Int] {
            selectedGoals = goalRaws.compactMap { OnboardingGoal(rawValue: $0) }
        }
        if let levelRaw = defaults.object(forKey: Self.resumeLevelKey) as? Int,
           let level = SpeakerLevel(rawValue: levelRaw) {
            speakerLevel = level
            hasPickedLevel = true
            vocabWords = Self.vocabSeeds(for: level)
        }
    }

    private func persistProgress() {
        let defaults = UserDefaults.standard
        defaults.set(currentStep.rawValue, forKey: Self.resumeStepKey)
        defaults.set(trimmedName, forKey: Self.resumeNameKey)
        defaults.set(selectedGoals.map(\.rawValue), forKey: Self.resumeGoalsKey)
        defaults.set(speakerLevel.rawValue, forKey: Self.resumeLevelKey)
    }

    static func clearResumeState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: resumeStepKey)
        defaults.removeObject(forKey: resumeNameKey)
        defaults.removeObject(forKey: resumeGoalsKey)
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

    /// Add or remove a goal. Nothing navigates: the goal step is multi-select,
    /// so the flow cannot know the answer is finished until the user says so.
    /// The old behaviour (pick, wait a beat, jump) read as the app deciding for
    func toggleGoal(_ goal: OnboardingGoal) {
        if let index = selectedGoals.firstIndex(of: goal) {
            guard selectedGoals.count > 1 else {
                Haptics.warning()
                return
            }
            selectedGoals.remove(at: index)
            Haptics.light()
        } else {
            guard !hasReachedGoalLimit else {
                Haptics.warning()
                return
            }
            selectedGoals.append(goal)
            Haptics.selection()
        }
        persistProgress()
    }

    func selectLevel(_ level: SpeakerLevel) {
        Haptics.selection()
        hasPickedLevel = true
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

    func resumeMicTestIfPermitted() async {
        guard hasMicPermission, levelMonitorTask == nil else { return }
        await startMicTest()
    }

    private func startMicTest() async {
        do {
            _ = try await audioService.startRecording()
        } catch {
            logger.error("Onboarding mic test failed to start: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return
        }
        startLevelMonitor(forBaselineTake: false)
    }

    func stopMicTest() {
        levelMonitorTask?.cancel()
        levelMonitorTask = nil
        audioService.cancelRecording()
        micLevel = 0
    }

    private func startLevelMonitor(forBaselineTake: Bool) {
        levelMonitorTask?.cancel()
        levelMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let dbfs = self.audioService.getAudioLevel()
                let normalized = max(0, min(1, (Double(dbfs) + 60) / 60))
                let smoothed = Float(pow(normalized, 0.7))
                self.micLevel = smoothed
                if smoothed > 0.18, !self.hasHeardVoice {
                    self.hasHeardVoice = true
                }
                if forBaselineTake {
                    let seconds = Int(self.audioService.recordingDuration)
                    if seconds != self.baselineElapsed {
                        self.baselineElapsed = seconds
                    }
                    self.baselineSampleCounter += 1
                    if self.baselineSampleCounter >= 8 {
                        self.baselineSampleCounter = 0
                        self.baselineLevelSamples.append(dbfs)
                    }
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    // MARK: Baseline Take

    var micPermissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// 3-2-1 in the record button, then the take starts. The countdown lives
    /// here (not in `CountdownOverlayView`) so the prompt card never leaves
    /// the screen — the take begins on a page the user is already reading.
    func beginBaselineCountdown() {
        guard baselinePhase == .ready else { return }
        baselineNote = nil
        Haptics.medium()
        baselinePhase = .countdown
        baselineCountdownValue = 3
        baselineCountdownTask?.cancel()
        baselineCountdownTask = Task { [weak self] in
            for tick in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.baselineCountdownValue = tick
                Haptics.light()
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            await self.startBaselineTake()
        }
    }

    private func startBaselineTake() async {
        do {
            _ = try await audioService.startRecording()
        } catch {
            baselinePhase = .ready
            baselineNote = "The recorder couldn't start. Try again."
            return
        }
        baselineElapsed = 0
        baselineLevelSamples = []
        baselineSampleCounter = 0
        baselinePhase = .recording
        Haptics.heavy()
        UIApplication.shared.isIdleTimerDisabled = true
        startLevelMonitor(forBaselineTake: true)
    }

    func finishBaselineTake() async -> (url: URL, duration: TimeInterval, levelSamples: [Float])? {
        guard baselinePhase == .recording else { return nil }
        baselinePhase = .saving
        levelMonitorTask?.cancel()
        levelMonitorTask = nil
        micLevel = 0
        UIApplication.shared.isIdleTimerDisabled = false
        Haptics.success()
        let url = await audioService.stopRecording()
        let duration = audioService.recordingDuration
        guard let url else {
            baselinePhase = .ready
            baselineNote = "That take didn't save. Give it another go."
            return nil
        }
        return (url, duration, baselineLevelSamples)
    }

    func discardBaselineTake(note: String? = nil) {
        baselineCountdownTask?.cancel()
        baselineCountdownTask = nil
        levelMonitorTask?.cancel()
        levelMonitorTask = nil
        micLevel = 0
        UIApplication.shared.isIdleTimerDisabled = false
        audioService.cancelRecording()
        baselineElapsed = 0
        baselinePhase = .ready
        baselineNote = note
    }

    // MARK: Voice Calibration

    func startCalibration() {
        Haptics.medium()
        showingCalibration = true
    }

    func applyCalibration(_ profile: VoiceProfile) {
        voiceProfile = profile
    }

    // MARK: Notification Permission

    func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        hasNotificationPermission = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
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
            logger.error("Notification permission error: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    // MARK: Result

    func makeResult(baselineRecordingID: UUID? = nil, reviewBaseline: Bool = false) -> OnboardingResult {
        AnalyticsService.shared.log(.onboardingStep(currentStep.analyticsName, action: "complete"))
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        var finalDictionary = dictionaryWords
        if !trimmedName.isEmpty,
           !finalDictionary.contains(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            finalDictionary.append(trimmedName)
        }
        return OnboardingResult(
            userName: trimmedName,
            // Never empty downstream: a user who skipped the goal step still
            // needs a mix, and everyday talk is the least presumptuous default.
            goals: selectedGoals.isEmpty ? [.everydayConfidence] : selectedGoals,
            speakerLevel: speakerLevel,
            vocabWords: vocabWords,
            dictionaryWords: finalDictionary,
            reminderEnabled: reminderEnabled && hasNotificationPermission,
            reminderHour: comps.hour ?? 9,
            reminderMinute: comps.minute ?? 0,
            baselineRecordingID: baselineRecordingID,
            reviewBaselineOnFinish: reviewBaseline,
            voiceProfile: voiceProfile
        )
    }

    private static func defaultReminderTime() -> Date {
        var comps = DateComponents()
        comps.hour = 9
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}

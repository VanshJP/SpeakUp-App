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

    /// Whether the user can navigate back from this step. The terminal
    /// `baseline` step is one-way: retakes happen inside it, and backing out
    /// mid-take would tear down a live recording.
    var allowsBack: Bool {
        switch self {
        case .welcome, .baseline: return false
        default: return true
        }
    }

    /// Hero steps run their own full-bleed layout instead of the shared
    /// `OnboardingPage` header, carry no step counter, and hide the tick
    /// meter. The baseline is the event the counted steps build toward, so it
    /// is deliberately not a step among steps.
    var isHero: Bool {
        switch self {
        case .welcome, .baselineBriefing, .baseline: return true
        default: return false
        }
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

    /// Steps a first run walks. The flow ends inside the baseline recording —
    /// the first guided take, its analysis, and its reveal — rather than
    /// handing the user off to an unguided recorder after a recap screen.
    ///
    /// `calibrate`, `intelligence`, and `reminder` are deliberately absent.
    /// Each one asks for effort, storage, or a system permission before the
    /// user has seen a single score, and the score is the only thing that has
    /// earned any of it. All three keep working and are offered again on
    /// `FirstRecordingSetupSheet`, immediately after the first session.
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

/// Final picks the user makes during onboarding. Returned to `ContentView`
/// so it can apply them to the persisted `UserSettings` row in one shot.
struct OnboardingResult {
    let userName: String
    /// Goals in pick order, at least one. Drives the prompt category mix on
    /// Today (see `PromptMix`); the first entry is stored as the primary goal.
    let goals: [OnboardingGoal]
    let speakerLevel: SpeakerLevel
    let vocabWords: [String]
    let dictionaryWords: [String]
    let reminderEnabled: Bool
    let reminderHour: Int
    let reminderMinute: Int
    /// The baseline recording captured inside onboarding. Nil when the user
    /// bailed before recording (mic denied, "explore first").
    let baselineRecordingID: UUID?
    /// True when the reveal's "See my full breakdown" was tapped — ContentView
    /// routes straight into the recording detail after dismissing.
    let reviewBaselineOnFinish: Bool
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

    // Practice intent. Multi-select: someone preparing for interviews who also
    // wants everyday confidence is one user, not two, and the prompt mix can
    // weight both. Ordered so the first pick stays the primary goal.
    var selectedGoals: [OnboardingGoal] = []
    /// Ceiling on picks. Past three the weighting stops meaning anything —
    /// every category ends up favored, which is the same as none of them.
    static let maxGoals = 3
    var speakerLevel: SpeakerLevel = .intermediate
    /// The level step shows an unpicked state until the user chooses, even
    /// though `speakerLevel` carries a default for everything downstream.
    var hasPickedLevel = false

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

    // Vocab + dictionary seeds. Seeded silently from the level pick — the
    // editing page was homework mid-flow; the Word Bank in Settings is the
    // editor now.
    var vocabWords: [String] = OnboardingViewModel.vocabSeeds(for: .intermediate)
    var dictionaryWords: [String] = []

    // MARK: Baseline take

    /// The guided first take. `ready → countdown → recording`; everything after
    /// stop (persist, analyze, reveal) is view-owned because it needs the
    /// model context.
    enum BaselinePhase {
        /// `saving` covers the gap between the user pressing Done and the
        /// `Recording` row existing — stopping the file takes long enough to
        /// see. Without it the take screen fell back to `ready` for a few
        /// frames and the pre-record UI flashed back over a finished take.
        case ready, countdown, recording, saving
    }

    var baselinePhase: BaselinePhase = .ready
    var baselineCountdownValue = 3
    /// Whole seconds only — the recorder UI is 1 Hz, so writing fractional
    /// elapsed would re-diff the page 16 times a second for nothing.
    var baselineElapsed: Int = 0
    /// One-line status shown on the ready state after a discarded or failed
    /// take ("We saved nothing — clean slate.").
    var baselineNote: String?
    private var baselineCountdownTask: Task<Void, Never>?
    /// dBFS samples at ~0.5s cadence, matching what `RecordingViewModel`
    /// collects for the volume/energy metrics.
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

    // v8 keys: the goal draft is a list now, not one Int. Reading a v7 scalar
    // into it would silently restore a single goal and lose the shape, so the
    // bump invalidates the old drafts instead — same reason v7 existed.
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

    /// The steps that carry a counter and a tick: the four questions between
    /// the cover and the baseline. The hero bookends aren't counted — the
    /// baseline is the destination, not a step among steps.
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

    /// Wipes draft state once onboarding has been applied. Called by
    /// `ContentView` after `applyOnboardingResult` succeeds.
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

    /// Add or remove a goal. Nothing navigates: the goal step is multi-select,
    /// so the flow cannot know the answer is finished until the user says so.
    /// The old behaviour (pick, wait a beat, jump) read as the app deciding for
    /// you, and made a second pick a race against the timer.
    ///
    /// Deselecting the last remaining goal is refused rather than allowed and
    /// then blocked at the CTA — leaving the step un-answerable after it was
    /// answered is a worse state than a tap that declines to do anything.
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
        startLevelMonitor(forBaselineTake: false)
    }

    func stopMicTest() {
        levelMonitorTask?.cancel()
        levelMonitorTask = nil
        audioService.cancelRecording()
        micLevel = 0
    }

    /// One monitor loop shared by the mic test and the baseline take. The
    /// baseline variant additionally tracks whole-second elapsed time and
    /// collects ~0.5s dBFS samples for the volume/energy metrics.
    private func startLevelMonitor(forBaselineTake: Bool) {
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

    /// Finalizes the take. Returns the audio to persist; the caller owns the
    /// model context, so the `Recording` row is created view-side.
    func finishBaselineTake() async -> (url: URL, duration: TimeInterval, levelSamples: [Float])? {
        guard baselinePhase == .recording else { return nil }
        // Also doubles as the re-entrancy guard: a second Done tap during the
        // stop no longer passes the guard above.
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
        // Stays `.saving` on success — the caller swaps the whole page to the
        // analyzing view, so returning to `ready` would only flash the recorder.
        return (url, duration, baselineLevelSamples)
    }

    /// Start over, interruption, or backgrounding mid-take. Deletes the audio
    /// and resets to ready; `note` explains what happened in the coach's voice.
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

    func makeResult(baselineRecordingID: UUID? = nil, reviewBaseline: Bool = false) -> OnboardingResult {
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

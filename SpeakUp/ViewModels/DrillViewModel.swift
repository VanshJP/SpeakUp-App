import Foundation
import SwiftUI

@Observable
@MainActor
class DrillViewModel {
    // Reuse the same audio services as RecordingViewModel
    let audioService = AudioService()
    let liveTranscriptionService = LiveTranscriptionService()

    var selectedMode: DrillMode?
    var isActive = false
    var timeRemaining: Int = 0
    var score: Int = 0
    var result: DrillResult?
    var isComplete = false
    /// Pace-control target from the user's settings (default 150).
    var targetWPM: Int = 150
    /// Set when the audio/recognition stack can't run (mic denied, speech
    /// recognition off, dead engine). The session view surfaces it and exits - 
    /// a drill that can't hear must not end as a confident clean run.
    var errorMessage: String?

    // Audio level for waveform visualization (same as RecordingViewModel)
    var audioLevel: Float = -160

    // Live metrics derived from transcription service
    var liveFillerCount: Int { liveTranscriptionService.liveFillerCount }
    var liveWordCount: Int { liveTranscriptionService.liveWordCount }

    var liveWPM: Double {
        let elapsed = Double(totalDuration - timeRemaining)
        guard elapsed > 2 else { return 0 }
        return Double(liveWordCount) / elapsed * 60
    }

    // Pause Practice state
    var pauseMarkerActive = false
    var pauseMarkersHit = 0
    let pauseMarkersTotal = 3
    private let pauseWindowDuration = 3
    private var pauseTimings: [Int] = []
    private var silentFramesInPause = 0
    private var totalFramesInPause = 0
    /// Metering frames between the markers, and how many of them had a voice
    /// in them. A pause is only a pause next to speech.
    private var framesOutsidePause = 0
    private var voicedFramesOutsidePause = 0
    private static let minimumVoicedRatio = 0.25

    /// What to talk about this round - a topic, a line to read, or a
    /// question, depending on the drill. Every drill has one now; see
    /// `DefaultDrillPrompts`.
    var impromptuPrompt: String = ""

    /// Word the emphasis drill wants stressed (uppercase in the prompt line).
    var emphasisTargetWord: String = ""
    /// True while post-stop pitch analysis is still running.
    var isAnalyzingPitch = false
    /// Live peak-over-median energy swing (dB) for emphasis / variety HUD.
    private(set) var liveEnergySwing: Double = 0
    private var levelSamples: [Float] = []

    // Pace Control state

    /// Seconds of speech the live pace is measured over. The drill used to
    /// show words per minute since the start, which barely moves once a few
    /// seconds are in: speeding up at the forty-second mark read as no change.
    static let paceWindowSeconds = 10
    /// Either side of the target that still counts as on pace.
    static let paceBand = 20.0
    /// Words per minute over the last `paceWindowSeconds`, or since the start
    /// until that much has elapsed.
    private(set) var rollingWPM: Double = 0
    /// Words heard by the end of each elapsed second.
    private var wordsBySecond: [Int] = []
    private var paceSecondsInBand = 0
    private var paceSecondsMeasured = 0

    private var timer: Timer?
    private var audioLevelTimer: Timer?
    private var totalDuration: Int = 0
    /// The ladder rung the current run uses.
    private var runningLevel = 0
    /// Whether live transcription is actually running for this drill. Pause
    /// Practice scores from mic metering alone; transcription-scored modes
    /// from transcription, so a silent death there must end the drill early
    /// rather than let the clock run out on zeros.
    private var transcriptionLive = false

    /// Lifetime drill count. Held in UserDefaults rather than on the view model
    /// because a fresh instance is built per sheet presentation, and a counter
    /// that resets every time the sheet opens buckets everything as "1".
    private static let startCountKey = "analytics.drillsStarted"
    private var drillsStarted: Int {
        get { UserDefaults.standard.integer(forKey: Self.startCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.startCountKey) }
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - Double(timeRemaining) / Double(totalDuration)
    }

    /// Timed structure cue for Impromptu (PREP) and Q&A (CLEAR-lite).
    var structureBeat: String? {
        guard let mode = selectedMode, isActive else { return nil }
        let p = progress
        switch mode {
        case .impromptuSprint:
            if p < 0.25 { return "Point" }
            if p < 0.50 { return "Reason" }
            if p < 0.75 { return "Example" }
            return "Point"
        case .qaSprint:
            if p < 0.20 { return "Clarify" }
            if p < 0.45 { return "Answer" }
            if p < 0.75 { return "Support" }
            return "Close"
        default:
            return nil
        }
    }

    // MARK: - Start Drill

    /// - Parameter level: The rung of the drill's ladder to run. Nil runs
    ///   the longest one unlocked - what the drill list shows.
    func startDrill(mode: DrillMode, level: Int? = nil) {
        selectedMode = mode
        let unlocked = DrillProgressStore.record(for: mode)?.level ?? 0
        runningLevel = min(max(0, level ?? unlocked), max(0, mode.durationLadder.count - 1))
        totalDuration = mode.durationSeconds(atLevel: runningLevel)
        timeRemaining = totalDuration
        score = 0
        isActive = true
        isComplete = false
        result = nil
        errorMessage = nil
        transcriptionLive = false
        isAnalyzingPitch = false
        liveEnergySwing = 0
        levelSamples = []
        resetPace()

        // Pause Practice: schedule 3 pause windows evenly across the drill
        pauseMarkerActive = false
        pauseMarkersHit = 0
        silentFramesInPause = 0
        totalFramesInPause = 0
        framesOutsidePause = 0
        voicedFramesOutsidePause = 0
        if mode == .pausePractice {
            let spacing = totalDuration / (pauseMarkersTotal + 1)
            pauseTimings = (1...pauseMarkersTotal).map { i in
                totalDuration - (spacing * i)
            }
        } else {
            pauseTimings = []
        }

        // Keep the topic picked at selection time, so the prep countdown can
        // show it and a retry stays fair; only fall back to a fresh pick when
        // entering without one (a lesson launches the session directly).
        if impromptuPrompt.isEmpty {
            preparePrompt(for: mode)
        }

        Task {
            if await startAudio() {
                startTimer()
            }
        }
    }

    func preparePrompt(for mode: DrillMode) {
        emphasisTargetWord = ""
        switch mode {
        case .fillerElimination, .paceControl, .pausePractice:
            impromptuPrompt = DefaultDrillPrompts.familiarTopics.randomElement()
                ?? "Walk through your morning routine, step by step"
        case .impromptuSprint:
            impromptuPrompt = DefaultDrillPrompts.impromptuTopics.randomElement()
                ?? "Talk about anything!"
        case .vocalVariety:
            impromptuPrompt = DefaultDrillPrompts.vocalVarietyLines.randomElement()
                ?? "Glide your pitch from low to high on this sentence."
        case .emphasis:
            let pick = DefaultDrillPrompts.emphasisPrompts.randomElement()
                ?? ("I am absolutely CERTAIN this will work.", "CERTAIN")
            impromptuPrompt = pick.line
            emphasisTargetWord = pick.target
        case .qaSprint:
            impromptuPrompt = DefaultDrillPrompts.qaQuestions.randomElement()
                ?? "What's the biggest challenge in your field right now?"
        }
    }

    private func startAudio() async -> Bool {
        do {
            // Start the recorder so the audio session is active. Throws on
            // mic-permission denial - surfaced, never swallowed.
            _ = try await audioService.startRecording()
        } catch {
            errorMessage = "Microphone unavailable: \(error.localizedDescription). Check Settings → Privacy → Microphone."
            isActive = false
            return false
        }

        // Drills never produce a `Recording`, so the session number they
        // report is the drill count, not a position in the practice log.
        drillsStarted += 1
        AnalyticsService.shared.log(
            .practiceStarted(useCase: "drill", sessionNumber: drillsStarted)
        )

        // Start audio level monitoring (same as RecordingViewModel)
        startAudioLevelMonitoring()

        let authorized = await liveTranscriptionService.requestAuthorization()
        guard authorized else {
            if selectedMode?.allowsMeteringOnly == true {
                // Pause Practice / Vocal Variety can score without ASR.
                return true
            }
            errorMessage = "Speech recognition is off for this app. Enable it in Settings to run this drill."
            isActive = false
            return false
        }

        liveTranscriptionService.start()
        transcriptionLive = liveTranscriptionService.isActive
        return true
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        // Weak in the timer's block too. A `[weak self]` only on the inner
        // task makes this block hold `self` strongly, so the run loop kept the
        // view model alive and ticking until something called `cleanup()`.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isActive else { return }

        // Recognition dying mid-drill (interruption, recognizer loss) must end
        // the scoring window now - letting the clock run on produces silent
        // zeros for every mode that scores from transcription.
        if transcriptionLive, selectedMode?.allowsMeteringOnly != true,
           !liveTranscriptionService.isActive {
            finishDrill(endedEarly: true)
            return
        }

        // Decrement-then-finish inside the same tick: finishing on a later
        // tick stretched every drill one second past its advertised length.
        if timeRemaining > 1 {
            timeRemaining -= 1
            if selectedMode == .pausePractice {
                updatePauseState()
            }
            if selectedMode == .paceControl {
                samplePace()
            }
        } else {
            timeRemaining = 0
            finishDrill()
        }
    }

    // MARK: - Pause Detection

    private func updatePauseState() {
        let nowActive = pauseTimings.contains { start in
            timeRemaining <= start && timeRemaining > start - pauseWindowDuration
        }

        if nowActive && !pauseMarkerActive {
            pauseMarkerActive = true
            silentFramesInPause = 0
            totalFramesInPause = 0
            Haptics.light()
        } else if !nowActive && pauseMarkerActive {
            pauseMarkerActive = false
            evaluatePauseWindow()
        }
    }

    private func evaluatePauseWindow() {
        let ratio = totalFramesInPause > 0
            ? Double(silentFramesInPause) / Double(totalFramesInPause)
            : 0
        if ratio > 0.5 {
            pauseMarkersHit += 1
            Haptics.success()
        } else {
            Haptics.warning()
        }
        silentFramesInPause = 0
        totalFramesInPause = 0
    }

    // MARK: - Pace

    /// One sample per elapsed second. Once a full window is in hand, each
    /// second is also judged against the target band - that is what the
    /// score's steadiness half measures.
    private func samplePace() {
        wordsBySecond.append(liveWordCount)
        let elapsed = wordsBySecond.count
        let window = Self.paceWindowSeconds
        guard elapsed > window else {
            rollingWPM = liveWPM
            return
        }
        let recent = wordsBySecond[elapsed - 1] - wordsBySecond[elapsed - 1 - window]
        rollingWPM = Double(recent) / Double(window) * 60
        paceSecondsMeasured += 1
        if abs(rollingWPM - Double(targetWPM)) <= Self.paceBand {
            paceSecondsInBand += 1
        }
    }

    private func resetPace() {
        rollingWPM = 0
        wordsBySecond = []
        paceSecondsInBand = 0
        paceSecondsMeasured = 0
    }

    // MARK: - Audio Level Monitoring (reuses same approach as RecordingViewModel)

    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.audioLevel = self.audioService.getAudioLevel()
                if self.pauseMarkerActive {
                    self.totalFramesInPause += 1
                    if self.audioLevel < -40 {
                        self.silentFramesInPause += 1
                    }
                } else if self.isActive, self.selectedMode == .pausePractice {
                    self.framesOutsidePause += 1
                    if self.audioLevel >= -40 {
                        self.voicedFramesOutsidePause += 1
                    }
                }
                if self.isActive {
                    self.levelSamples.append(self.audioLevel)
                    if self.levelSamples.count > 600 {
                        self.levelSamples.removeFirst(self.levelSamples.count - 600)
                    }
                    self.liveEnergySwing = Self.energySwing(in: self.levelSamples)
                }
            }
        }
    }

    /// Peak-minus-median of recent dB samples - a crude live stand-in for
    /// "are you actually changing energy," not a final score.
    private static func energySwing(in samples: [Float]) -> Double {
        let voiced = samples.filter { $0 > -50 }
        guard voiced.count >= 8 else { return 0 }
        let sorted = voiced.sorted()
        let median = sorted[sorted.count / 2]
        let peak = sorted.last ?? median
        return Double(max(0, peak - median))
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = -160
    }

    // MARK: - Finish Drill

    func finishDrill(endedEarly: Bool = false) {
        // Only the live session may finish - pitch analysis re-entry must not
        // stopRecording twice or publish a duplicate result.
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil

        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()

        guard let mode = selectedMode else {
            audioService.cancelRecording()
            return
        }

        // Flush any in-progress pause window before scoring
        if mode == .pausePractice && pauseMarkerActive {
            pauseMarkerActive = false
            evaluatePauseWindow()
        }

        if mode.usesPitchAnalysis {
            isAnalyzingPitch = true
            Task { await finishWithPitchAnalysis(mode: mode, endedEarly: endedEarly) }
            return
        }

        audioService.cancelRecording() // discard - drills don't keep takes
        publishResult(mode: mode, endedEarly: endedEarly, pitch: nil)
    }

    private func finishWithPitchAnalysis(mode: DrillMode, endedEarly: Bool) async {
        // A drill take is read once and deleted, so it never goes to iCloud.
        let url = await audioService.stopRecording(promoteToICloud: false)
        defer { isAnalyzingPitch = false }

        // Decode, analysis and delete all off the main actor. The decode used
        // to run here on it: a whole take of AAC, synchronously.
        var pitch: PitchMetrics?
        if let url {
            pitch = await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: url) }
                return MonoPCM.decode(url: url).flatMap { PitchAnalysisService.analyze(monoPCM: $0) }
            }.value
        }

        // Silence is not a score - no voiced frames → honest failure notice.
        if pitch == nil || (pitch?.voicedFrameRatio ?? 0) < 0.05 {
            result = DrillResult(
                mode: mode,
                score: 0,
                date: Date(),
                details: endedEarly
                    ? "No clear voice detected. Recognition stopped early."
                    : "No clear voice detected. Try speaking closer to the mic.",
                passed: false
            )
            score = 0
            isComplete = true
            CurriculumActivitySignalStore.markDrillCompleted(mode.rawValue)
            Haptics.warning()
            return
        }

        publishResult(mode: mode, endedEarly: endedEarly, pitch: pitch)
    }

    private func publishResult(mode: DrillMode, endedEarly: Bool, pitch: PitchMetrics?) {
        let elapsed = Double(totalDuration - timeRemaining)
        let finalFillerCount = liveFillerCount
        let finalWPM = elapsed > 2 ? Double(liveWordCount) / elapsed * 60 : 0
        // Ran to the bell rather than tapping out. Only a full round can earn
        // the next rung of a duration ladder.
        let completedRound = timeRemaining == 0

        let drillScore: Int
        var details: String
        let passed: Bool

        switch mode {
        case .fillerElimination:
            // Silence has no fillers in it, and used to pass as a clean run.
            let spokeEnough = liveWordCount >= max(5, totalDuration / 3)
            if !spokeEnough {
                drillScore = 0
                passed = false
                details = "Too little speech to score. Keep talking for the whole round."
            } else if finalFillerCount == 0 && completedRound {
                drillScore = 100
                passed = true
                details = "Clean run: zero fillers in \(totalDuration) seconds"
            } else if finalFillerCount == 0 {
                // Clean, but tapped out early: the score is the share of the
                // round that was actually spoken, so the ring and the verdict
                // agree.
                drillScore = min(99, Int((elapsed / Double(max(1, totalDuration)) * 100).rounded()))
                passed = false
                details = "Clean for \(Int(elapsed)) seconds. Run the full round to clear it."
            } else {
                drillScore = max(0, 100 - finalFillerCount * 25)
                passed = false
                let words = fillerBreakdown.map { ": \($0)" } ?? ""
                details = "\(finalFillerCount) filler\(finalFillerCount == 1 ? "" : "s")\(words). Swap each one for a closed-mouth pause."
            }

        case .paceControl:
            let sigma = 35.0
            let target = Double(targetWPM)
            let deviation = finalWPM - target
            let closeness = 100.0 * exp(-(deviation * deviation) / (2 * sigma * sigma))
            // Holding the pace is the skill, not averaging it: a take that
            // swings from 110 to 190 can still average 150.
            if paceSecondsMeasured > 0 {
                let steadiness = Double(paceSecondsInBand) / Double(paceSecondsMeasured)
                drillScore = max(0, Int((0.6 * closeness + 0.4 * steadiness * 100).rounded()))
                details = "Average pace: \(Int(finalWPM)) WPM (target: \(targetWPM)) · on pace \(Int((steadiness * 100).rounded()))% of the time"
            } else {
                drillScore = max(0, Int(closeness))
                details = "Average pace: \(Int(finalWPM)) WPM (target: \(targetWPM))"
            }
            passed = drillScore >= 70

        case .pausePractice:
            // The markers score silence, so a silent take used to hit all
            // three. The pauses only mean something between stretches of
            // speech.
            let voicedRatio = framesOutsidePause > 0
                ? Double(voicedFramesOutsidePause) / Double(framesOutsidePause)
                : 0
            if voicedRatio < Self.minimumVoicedRatio {
                drillScore = 0
                passed = false
                details = "We didn't hear you speaking between the markers. Talk through the round and go quiet only when a marker lights."
            } else {
                drillScore = pauseMarkersTotal > 0
                    ? Int(Double(pauseMarkersHit) / Double(pauseMarkersTotal) * 100)
                    : 0
                passed = pauseMarkersHit >= 2
                if pauseMarkersHit == pauseMarkersTotal {
                    details = "All \(pauseMarkersTotal) pause markers hit"
                } else {
                    details = "Hit \(pauseMarkersHit) of \(pauseMarkersTotal) pause markers"
                }
            }

        case .impromptuSprint:
            // Too little speech scores zero, not the fifty-point floor: a
            // silent sprint used to show a full ring over "too little speech".
            passed = finalFillerCount <= 2 && liveWordCount >= 8
            drillScore = liveWordCount < 8 ? 0 : max(50, 100 - finalFillerCount * 10)
            details = liveWordCount < 8
                ? "Too little speech to score the sprint"
                : "Spoke with \(finalFillerCount) filler(s) on a PREP-cued topic"

        case .vocalVariety:
            let variation = pitch?.pitchVariationScore ?? 0
            let range = Double(pitch?.f0RangeSemitones ?? 0)
            drillScore = variation
            passed = variation >= 60 && range >= 3
            details = String(
                format: "Pitch variation %d/100 · range %.1f semitones",
                variation,
                range
            )

        case .emphasis:
            let swing = Self.energySwing(in: levelSamples)
            // ~8-20 dB of peak-vs-median swing reads as intentional stress.
            let swingScore = min(100, Int(swing * 6))
            let saidSomething = liveWordCount >= 4
            drillScore = saidSomething ? max(20, swingScore) : 0
            passed = saidSomething && swingScore >= 55
            let target = emphasisTargetWord.isEmpty ? "the marked word" : emphasisTargetWord
            details = saidSomething
                ? "Energy swing on “\(target)”: \(Int(swing)) dB peak-over-median"
                : "No speech detected. Emphasis needs a full sentence."

        case .qaSprint:
            passed = finalFillerCount <= 2 && liveWordCount >= 10
            drillScore = liveWordCount < 10 ? 0 : max(50, 100 - finalFillerCount * 10)
            details = liveWordCount < 10
                ? "Answer was too short to score"
                : "Q&A answer with \(finalFillerCount) filler(s) · CLEAR beats"
        }

        if endedEarly {
            details += ". Recognition stopped early."
        }

        let clearedRound = passed && completedRound
        let progress = DrillProgressStore.recordRun(
            mode: mode,
            score: drillScore,
            passed: clearedRound,
            ranLevel: runningLevel
        )

        result = DrillResult(
            mode: mode,
            score: drillScore,
            date: Date(),
            details: details,
            passed: passed,
            milestone: Self.milestone(
                for: mode,
                score: drillScore,
                previous: progress.previous,
                updated: progress.updated
            ),
            level: runningLevel,
            longerRoundSeconds: Self.longerRound(
                for: mode,
                ranLevel: runningLevel,
                cleared: clearedRound,
                unlockedLevel: progress.updated.level
            )
        )
        score = drillScore
        isComplete = true
        CurriculumActivitySignalStore.markDrillCompleted(mode.rawValue)
        // No haptic here: `DrillResultView` lands one with its count-up, and
        // firing both buzzed twice for a single result.
    }

    /// "“um” ×2, “like” ×1" - which fillers this run leaned on, most frequent
    /// first. Knowing *which* one is the awareness half of habit reversal.
    private var fillerBreakdown: String? {
        let counts = liveTranscriptionService.liveFillerWordCounts
            .filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard !counts.isEmpty else { return nil }
        return counts.prefix(3)
            .map { "“\($0.key)” ×\($0.value)" }
            .joined(separator: ", ")
    }

    /// The line the result screen calls out: a longer round unlocked, or a
    /// personal best beaten. Nil on an ordinary run, and on a first run, which
    /// has nothing to beat.
    static func milestone(
        for mode: DrillMode,
        score: Int,
        previous: DrillRecord?,
        updated: DrillRecord
    ) -> String? {
        if updated.level > (previous?.level ?? 0) {
            return "Round cleared. \(mode.durationSeconds(atLevel: updated.level))-second rounds are unlocked."
        }
        if let previous, previous.runs > 0, score > previous.best {
            return "New personal best, up from \(previous.best)."
        }
        return nil
    }

    /// The next rung up, offered after a cleared round when it is open.
    /// Nil on a miss, on the top rung, and on a single-rung drill.
    static func longerRound(
        for mode: DrillMode,
        ranLevel: Int,
        cleared: Bool,
        unlockedLevel: Int
    ) -> Int? {
        let next = ranLevel + 1
        guard cleared, next < mode.durationLadder.count, next <= unlockedLevel else { return nil }
        return mode.durationSeconds(atLevel: next)
    }

    func cleanup() {
        timer?.invalidate()
        timer = nil
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()
        audioService.cleanup()
        // Fresh topic on the next selection; a kept topic would let "Try
        // Again" leak across different drill entries.
        impromptuPrompt = ""
        emphasisTargetWord = ""
        levelSamples = []
        liveEnergySwing = 0
        isAnalyzingPitch = false
        resetPace()
    }
}

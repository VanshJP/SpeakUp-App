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
    /// recognition off, dead engine). The session view surfaces it and exits —
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

    // Impromptu Sprint state
    var impromptuPrompt: String = ""
    private static let impromptuTopics = [
        "Describe your perfect weekend from start to finish",
        "Why is your favorite food the best one out there?",
        "Explain a hobby to someone who's never heard of it",
        "Convince someone to visit your favorite place",
        "Talk about a book or movie that changed your perspective",
        "What would you do with an extra hour each day?",
        "Describe your morning routine and why it works for you",
        "What's the best advice you've ever received?",
        "If you could have dinner with anyone, who and why?",
        "Pitch a brand new app idea in 30 seconds",
        "Talk about a skill you'd love to master and why",
        "Explain something interesting you learned recently",
        "Why should everyone try your favorite activity?",
        "Describe a place that feels like home to you",
        "What's one thing you'd change about how people communicate?",
        "Tell the story of your most memorable travel experience",
        "Explain why a simple everyday object is actually amazing",
        "What's a common misconception people have about your field?",
    ]

    private static let vocalVarietyLines = [
        "The storm rolled in, then the sky cracked open with light.",
        "Please lower your voice here, then lift it on the final word: victory.",
        "Start soft and low — then climb until the last phrase rings clear.",
        "Whisper the opening, speak the middle, project the close.",
        "Glide from your lowest comfortable note to your highest on this line.",
    ]

    private static let emphasisPrompts: [(line: String, target: String)] = [
        ("I am absolutely CERTAIN this will work.", "CERTAIN"),
        ("We need this done TODAY, not next week.", "TODAY"),
        ("That was the BEST decision we made all year.", "BEST"),
        ("Never underestimate a simple CLEAR answer.", "CLEAR"),
        ("This matters NOW more than it ever has.", "NOW"),
        ("She was the ONLY person who stayed.", "ONLY"),
    ]

    private static let qaQuestions = [
        "What's the biggest challenge in your field right now, and how would you solve it?",
        "Why should someone trust your recommendation?",
        "What would you do differently if you started over tomorrow?",
        "How do you explain your work to someone outside your field?",
        "What's one risk worth taking this year, and why?",
        "Where do most teams waste time — and what would you cut first?",
        "What does success look like for you in six months?",
        "How would you handle a question you don't know the answer to?",
    ]

    /// Word the emphasis drill wants stressed (uppercase in the prompt line).
    var emphasisTargetWord: String = ""
    /// True while post-stop pitch analysis is still running.
    var isAnalyzingPitch = false
    /// Live peak-over-median energy swing (dB) for emphasis / variety HUD.
    private(set) var liveEnergySwing: Double = 0
    private var levelSamples: [Float] = []

    private var timer: Timer?
    private var audioLevelTimer: Timer?
    private var totalDuration: Int = 0
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

    func startDrill(mode: DrillMode) {
        selectedMode = mode
        totalDuration = mode.defaultDurationSeconds
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

        // Pause Practice: schedule 3 pause windows evenly across the drill
        pauseMarkerActive = false
        pauseMarkersHit = 0
        silentFramesInPause = 0
        totalFramesInPause = 0
        if mode == .pausePractice {
            let spacing = totalDuration / (pauseMarkersTotal + 1)
            pauseTimings = (1...pauseMarkersTotal).map { i in
                totalDuration - (spacing * i)
            }
        } else {
            pauseTimings = []
        }

        // Prompted modes: keep the topic picked at selection time (so the
        // prep countdown can show it and retries stay fair); only fall back
        // to a fresh pick when entering without one.
        if mode.preparesPromptUpFront, impromptuPrompt.isEmpty {
            preparePrompt(for: mode)
        }

        Task {
            if await startAudio() {
                startTimer()
            }
        }
    }

    /// Picks the impromptu topic up front so the prep countdown can show it —
    /// the countdown is exactly when prep matters.
    func prepareImpromptuTopic() {
        preparePrompt(for: .impromptuSprint)
    }

    func preparePrompt(for mode: DrillMode) {
        switch mode {
        case .impromptuSprint:
            impromptuPrompt = Self.impromptuTopics.randomElement() ?? "Talk about anything!"
            emphasisTargetWord = ""
        case .vocalVariety:
            impromptuPrompt = Self.vocalVarietyLines.randomElement()
                ?? "Glide your pitch from low to high on this sentence."
            emphasisTargetWord = ""
        case .emphasis:
            let pick = Self.emphasisPrompts.randomElement()
                ?? ("I am absolutely CERTAIN this will work.", "CERTAIN")
            impromptuPrompt = pick.line
            emphasisTargetWord = pick.target
        case .qaSprint:
            impromptuPrompt = Self.qaQuestions.randomElement()
                ?? "What's the biggest challenge in your field right now?"
            emphasisTargetWord = ""
        default:
            break
        }
    }

    private func startAudio() async -> Bool {
        do {
            // Start the recorder so the audio session is active. Throws on
            // mic-permission denial — surfaced, never swallowed.
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isActive else { return }

        // Recognition dying mid-drill (interruption, recognizer loss) must end
        // the scoring window now — letting the clock run on produces silent
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

    /// Peak-minus-median of recent dB samples — a crude live stand-in for
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
        // Only the live session may finish — pitch analysis re-entry must not
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

        audioService.cancelRecording() // discard — drills don't keep takes
        publishResult(mode: mode, endedEarly: endedEarly, pitch: nil)
    }

    private func finishWithPitchAnalysis(mode: DrillMode, endedEarly: Bool) async {
        let url = await audioService.stopRecording()
        defer {
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            isAnalyzingPitch = false
        }

        var pitch: PitchMetrics?
        if let url, let pcm = MonoPCM.decode(url: url) {
            pitch = await Task.detached(priority: .userInitiated) {
                PitchAnalysisService.analyze(monoPCM: pcm)
            }.value
        }

        // Silence is not a score — no voiced frames → honest failure notice.
        if pitch == nil || (pitch?.voicedFrameRatio ?? 0) < 0.05 {
            result = DrillResult(
                mode: mode,
                score: 0,
                date: Date(),
                details: endedEarly
                    ? "No clear voice detected — ended early: recognition stopped"
                    : "No clear voice detected — try speaking closer to the mic",
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

        let drillScore: Int
        var details: String
        let passed: Bool

        switch mode {
        case .fillerElimination:
            drillScore = finalFillerCount == 0 ? 100 : max(0, 100 - finalFillerCount * 25)
            passed = finalFillerCount == 0
            details = finalFillerCount == 0
                ? "Clean run — zero fillers"
                : "\(finalFillerCount) filler(s) detected"

        case .paceControl:
            let sigma = 35.0
            let target = Double(targetWPM)
            let deviation = finalWPM - target
            drillScore = max(0, Int(100.0 * exp(-(deviation * deviation) / (2 * sigma * sigma))))
            passed = drillScore >= 70
            details = "Average pace: \(Int(finalWPM)) WPM (target: \(targetWPM))"

        case .pausePractice:
            drillScore = pauseMarkersTotal > 0
                ? Int(Double(pauseMarkersHit) / Double(pauseMarkersTotal) * 100)
                : 0
            passed = pauseMarkersHit >= 2
            if pauseMarkersHit == pauseMarkersTotal {
                details = "All \(pauseMarkersTotal) pause markers hit"
            } else {
                details = "Hit \(pauseMarkersHit) of \(pauseMarkersTotal) pause markers"
            }

        case .impromptuSprint:
            drillScore = max(50, 100 - finalFillerCount * 10)
            passed = finalFillerCount <= 2 && liveWordCount >= 8
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
            // ~8–20 dB of peak-vs-median swing reads as intentional stress.
            let swingScore = min(100, Int(swing * 6))
            let saidSomething = liveWordCount >= 4
            drillScore = saidSomething ? max(20, swingScore) : 0
            passed = saidSomething && swingScore >= 55
            let target = emphasisTargetWord.isEmpty ? "the marked word" : emphasisTargetWord
            details = saidSomething
                ? "Energy swing on “\(target)”: \(Int(swing)) dB peak-over-median"
                : "No speech detected — emphasis needs a full sentence"

        case .qaSprint:
            drillScore = max(50, 100 - finalFillerCount * 10)
            passed = finalFillerCount <= 2 && liveWordCount >= 10
            details = liveWordCount < 10
                ? "Answer was too short to score"
                : "Q&A answer with \(finalFillerCount) filler(s) · CLEAR beats"
        }

        if endedEarly {
            details += " — ended early: recognition stopped"
        }

        result = DrillResult(
            mode: mode,
            score: drillScore,
            date: Date(),
            details: details,
            passed: passed
        )
        score = drillScore
        isComplete = true
        CurriculumActivitySignalStore.markDrillCompleted(mode.rawValue)

        if passed {
            Haptics.success()
        } else {
            Haptics.warning()
        }
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
    }
}

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

    private var timer: Timer?
    private var audioLevelTimer: Timer?
    private var totalDuration: Int = 0
    /// Whether live transcription is actually running for this drill. Pause
    /// Practice scores from mic metering alone; the other three modes score
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

        // Impromptu Sprint: keep the topic picked at selection time (so the
        // prep countdown can show it and retries stay fair); only fall back
        // to a fresh pick when entering without one.
        if mode == .impromptuSprint, impromptuPrompt.isEmpty {
            impromptuPrompt = Self.impromptuTopics.randomElement() ?? "Talk about anything!"
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
        impromptuPrompt = Self.impromptuTopics.randomElement() ?? "Talk about anything!"
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
            if selectedMode != .pausePractice {
                errorMessage = "Speech recognition is off for this app. Enable it in Settings to run this drill."
                isActive = false
                return false
            }
            // Pause Practice scores silence from metering alone.
            return true
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
        if transcriptionLive, selectedMode != .pausePractice,
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
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = -160
    }

    // MARK: - Finish Drill

    func finishDrill(endedEarly: Bool = false) {
        isActive = false
        timer?.invalidate()
        timer = nil

        // Stop audio services
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()
        audioService.cancelRecording() // discard the audio file — drills don't save recordings

        guard let mode = selectedMode else { return }

        let elapsed = Double(totalDuration - timeRemaining)
        let finalFillerCount = liveFillerCount
        let finalWPM = elapsed > 2 ? Double(liveWordCount) / elapsed * 60 : 0

        let drillScore: Int
        var details: String
        let passed: Bool

        // Flush any in-progress pause window before scoring
        if mode == .pausePractice && pauseMarkerActive {
            pauseMarkerActive = false
            evaluatePauseWindow()
        }

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
            passed = finalFillerCount <= 2
            details = "Spoke with \(finalFillerCount) filler(s) on an impromptu topic"
        }

        // An early end is context the score needs, not a footnote.
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
    }
}

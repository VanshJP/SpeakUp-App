import Foundation
import SwiftUI

@Observable
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

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - Double(timeRemaining) / Double(totalDuration)
    }

    // MARK: - Permissions

    func checkPermissions() async -> Bool {
        return await audioService.requestPermission()
    }

    // MARK: - Start Drill

    @MainActor
    func startDrill(mode: DrillMode) {
        selectedMode = mode
        totalDuration = mode.defaultDurationSeconds
        timeRemaining = totalDuration
        score = 0
        isActive = true
        isComplete = false
        result = nil

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

        // Impromptu Sprint: pick a random topic
        if mode == .impromptuSprint {
            impromptuPrompt = Self.impromptuTopics.randomElement() ?? "Talk about anything!"
        }

        Task {
            await startAudio()
            startTimer()
        }
    }

    @MainActor
    private func startAudio() async {
        do {
            // Start the recorder so the audio session is active
            _ = try await audioService.startRecording()

            // Start audio level monitoring (same as RecordingViewModel)
            startAudioLevelMonitoring()

            // Start live transcription for filler/word detection
            let authorized = await liveTranscriptionService.requestAuthorization()
            if authorized {
                liveTranscriptionService.start()
            }
        } catch {
            print("DrillViewModel: failed to start audio: \(error)")
        }
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

    @MainActor
    private func tick() {
        guard isActive else { return }

        if timeRemaining > 0 {
            timeRemaining -= 1
            if selectedMode == .pausePractice {
                updatePauseState()
            }
        } else {
            finishDrill()
        }
    }

    // MARK: - Pause Detection

    @MainActor
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

    @MainActor
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
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
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

    @MainActor
    func finishDrill() {
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
        let details: String
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
            details = finalFillerCount == 0 ? "Perfect! Zero fillers!" : "\(finalFillerCount) filler(s) detected"

        case .paceControl:
            let deviation = abs(finalWPM - 150)
            drillScore = max(0, 100 - Int(deviation * 2))
            passed = deviation < 20
            details = "Average pace: \(Int(finalWPM)) WPM (target: 130-170)"

        case .pausePractice:
            drillScore = pauseMarkersTotal > 0
                ? Int(Double(pauseMarkersHit) / Double(pauseMarkersTotal) * 100)
                : 0
            passed = pauseMarkersHit >= 2
            if pauseMarkersHit == pauseMarkersTotal {
                details = "Perfect! Hit all \(pauseMarkersTotal) pause markers!"
            } else {
                details = "Hit \(pauseMarkersHit) of \(pauseMarkersTotal) pause markers"
            }

        case .impromptuSprint:
            drillScore = max(50, 100 - finalFillerCount * 10)
            passed = finalFillerCount <= 2
            details = "Spoke with \(finalFillerCount) filler(s) on an impromptu topic"
        }

        result = DrillResult(
            mode: mode,
            score: drillScore,
            date: Date(),
            details: details,
            passed: passed
        )
        isComplete = true

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
    }
}

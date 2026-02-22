import Foundation
import SwiftUI
import SwiftData

@Observable
class RecordingViewModel {
    // Services
    let audioService = AudioService()
    let liveTranscriptionService = LiveTranscriptionService()

    // State
    var isRecording = false
    var isPaused = false
    var recordingDuration: TimeInterval = 0
    var targetDuration: RecordingDuration = .sixty
    var prompt: Prompt?

    // Timer
    var remainingTime: TimeInterval = 60
    var progress: Double = 0
    var timerEndBehavior: TimerEndBehavior = .saveAndStop
    var countdownStyle: CountdownStyle = .countUp

    // Permissions
    var hasAudioPermission = false
    var showingPermissionAlert = false
    var permissionAlertMessage = ""

    // Result
    var recordingURL: URL?
    var isProcessing = false
    var error: Error?
    var autoSavedRecording: Recording?

    // Sentence-end grace period for Save & Stop
    var isWaitingForSentenceEnd = false
    private let sentenceSilenceThreshold: TimeInterval = 0.5  // silence gap to consider sentence ended
    private let silenceDbThreshold: Float = -40              // dB level below which counts as silence
    private let maxGracePeriod: TimeInterval = 10.0           // max extra seconds before force-stop
    private var graceStartTime: TimeInterval?

    // Audio level for waveform visualization
    var audioLevel: Float = -160

    // Audio level samples for volume analysis (collected every ~0.5s)
    var audioLevelSamples: [Float] = []
    private var audioLevelSampleCounter = 0

    // Live filler counter
    var liveFillerCount: Int { liveTranscriptionService.liveFillerCount }

    private var timer: Timer?
    private var audioLevelTimer: Timer?
    private var modelContext: ModelContext?

    func configure(
        with context: ModelContext,
        prompt: Prompt?,
        duration: RecordingDuration,
        timerEndBehavior: TimerEndBehavior = .saveAndStop,
        countdownStyle: CountdownStyle = .countUp
    ) {
        self.modelContext = context
        self.prompt = prompt
        self.targetDuration = duration
        self.remainingTime = TimeInterval(duration.seconds)
        self.timerEndBehavior = timerEndBehavior
        self.countdownStyle = countdownStyle
        self.progress = countdownStyle == .countDown ? 1.0 : 0.0
    }

    // MARK: - Permissions

    func checkPermissions() async {
        hasAudioPermission = await audioService.requestPermission()

        if !hasAudioPermission {
            permissionAlertMessage = "Microphone access is required to record audio."
            showingPermissionAlert = true
        }
    }

    // MARK: - Recording Control

    @MainActor
    func startRecording() async {
        do {
            recordingURL = try await audioService.startRecording()

            isRecording = true
            Haptics.medium()
            startTimer()
            startAudioLevelMonitoring()

            // Start live filler counting (after recorder is active so session is ready)
            let authorized = await liveTranscriptionService.requestAuthorization()
            if authorized {
                liveTranscriptionService.start()
            }
        } catch {
            self.error = error
        }
    }

    @MainActor
    func stopRecording() async -> Recording? {
        timer?.invalidate()
        timer = nil
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()

        isRecording = false
        isProcessing = true
        Haptics.success()

        defer { isProcessing = false }

        let finalURL = await audioService.stopRecording()
        let actualDuration = audioService.recordingDuration

        guard let url = finalURL, let context = modelContext else {
            return nil
        }

        // Create recording object
        let recording = Recording(
            prompt: prompt,
            targetDuration: targetDuration.seconds,
            actualDuration: actualDuration,
            mediaType: .audio,
            audioURL: url,
            isProcessing: true // Will be transcribed
        )

        context.insert(recording)

        do {
            try context.save()
            return recording
        } catch {
            self.error = error
            return nil
        }
    }

    func cancelRecording() {
        timer?.invalidate()
        timer = nil
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()

        audioService.cancelRecording()

        isRecording = false
        recordingURL = nil
    }

    // MARK: - Timer

    private func startTimer() {
        remainingTime = TimeInterval(targetDuration.seconds)
        progress = countdownStyle == .countDown ? 1.0 : 0.0

        // Brief pause so the user sees the full starting state
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                self.remainingTime -= 0.1
                self.recordingDuration = TimeInterval(self.targetDuration.seconds) - self.remainingTime

                // Haptic pulse at 10s and 5s remaining
                if abs(self.remainingTime - 10.0) < 0.1 {
                    Haptics.warning()
                } else if abs(self.remainingTime - 5.0) < 0.1 {
                    Haptics.heavy()
                }

                if self.remainingTime <= 0 {
                    // Clamp progress once timer expires
                    self.progress = self.countdownStyle == .countDown ? 0.0 : 1.0

                    if self.timerEndBehavior == .saveAndStop {
                        let timeSinceLastWord = self.recordingDuration - self.liveTranscriptionService.lastSegmentEndTime
                        let isQuiet = self.audioLevel < self.silenceDbThreshold

                        if !self.isWaitingForSentenceEnd {
                            // Timer just expired — check if user is mid-sentence
                            let isMidSentence = self.liveTranscriptionService.isActive
                                && self.liveTranscriptionService.lastSegmentEndTime > 0
                                && (timeSinceLastWord < self.sentenceSilenceThreshold || !isQuiet)

                            if isMidSentence {
                                // User is still speaking — enter grace period
                                self.isWaitingForSentenceEnd = true
                                self.graceStartTime = self.recordingDuration
                                Haptics.light()
                            } else {
                                // Not mid-sentence — stop immediately
                                self.timer?.invalidate()
                                self.timer = nil
                                self.autoSavedRecording = await self.stopRecording()
                            }
                        } else {
                            // Already in grace period — check for sentence end or timeout
                            let graceElapsed = self.recordingDuration - (self.graceStartTime ?? self.recordingDuration)

                            // Sentence ended = enough silence AND audio level is low
                            let sentenceEnded = timeSinceLastWord >= self.sentenceSilenceThreshold && isQuiet
                            let graceExpired = graceElapsed >= self.maxGracePeriod

                            if sentenceEnded || graceExpired {
                                self.isWaitingForSentenceEnd = false
                                self.graceStartTime = nil
                                self.timer?.invalidate()
                                self.timer = nil
                                self.autoSavedRecording = await self.stopRecording()
                            }
                        }
                    }
                    // .keepGoing: timer continues into negative, recording keeps going
                } else {
                    let rawProgress = 1 - (self.remainingTime / TimeInterval(self.targetDuration.seconds))
                    self.progress = self.countdownStyle == .countDown ? (1 - rawProgress) : rawProgress
                }
            }
            }
        }
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        audioLevelSampleCounter = 0
        audioLevelSamples = []
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let level = self.audioService.getAudioLevel()
                self.audioLevel = level
                // Collect sample every ~0.5s (every 10th tick at 0.05s interval)
                self.audioLevelSampleCounter += 1
                if self.audioLevelSampleCounter >= 10 {
                    self.audioLevelSampleCounter = 0
                    self.audioLevelSamples.append(level)
                }
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = -160
    }

    // MARK: - Computed Properties

    var isOvertime: Bool {
        remainingTime < 0 && timerEndBehavior == .keepGoing
    }

    /// The time value shown in the timer, accounting for countdown style.
    var displayTime: TimeInterval {
        if isOvertime {
            return abs(remainingTime)
        }
        switch countdownStyle {
        case .countDown:
            return max(0, remainingTime)
        case .countUp:
            return recordingDuration
        }
    }

    var formattedRemainingTime: String {
        if isOvertime {
            let overtimeSeconds = Int(abs(remainingTime))
            let minutes = overtimeSeconds / 60
            let seconds = overtimeSeconds % 60
            return String(format: "+%d:%02d", minutes, seconds)
        }
        let totalSeconds = Int(displayTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var timerLabel: String {
        if isOvertime { return "overtime" }
        return countdownStyle == .countDown ? "remaining" : "elapsed"
    }

    var timerColor: Color {
        if isOvertime {
            return .purple
        } else if remainingTime <= 10 {
            return .red
        } else if remainingTime <= 30 {
            return .orange
        }
        return .teal
    }

    // MARK: - Cleanup

    func cleanup() {
        timer?.invalidate()
        timer = nil
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()
        audioService.cleanup()
    }
}

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

    // Permissions
    var hasAudioPermission = false
    var showingPermissionAlert = false
    var permissionAlertMessage = ""

    // Result
    var recordingURL: URL?
    var isProcessing = false
    var error: Error?

    // Audio level for waveform visualization
    var audioLevel: Float = -160

    // Live filler counter
    var liveFillerCount: Int { liveTranscriptionService.liveFillerCount }

    private var timer: Timer?
    private var audioLevelTimer: Timer?
    private var modelContext: ModelContext?

    func configure(
        with context: ModelContext,
        prompt: Prompt?,
        duration: RecordingDuration
    ) {
        self.modelContext = context
        self.prompt = prompt
        self.targetDuration = duration
        self.remainingTime = TimeInterval(duration.seconds)
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
        progress = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                self.remainingTime -= 0.1
                self.progress = 1 - (self.remainingTime / TimeInterval(self.targetDuration.seconds))
                self.recordingDuration = TimeInterval(self.targetDuration.seconds) - self.remainingTime

                if self.remainingTime <= 0 {
                    // Invalidate timer BEFORE calling stop to prevent re-entry
                    self.timer?.invalidate()
                    self.timer = nil
                    _ = await self.stopRecording()
                }
            }
        }
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.audioLevel = self.audioService.getAudioLevel()
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = -160
    }

    // MARK: - Computed Properties

    var formattedRemainingTime: String {
        let totalSeconds = Int(max(0, remainingTime))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var timerColor: Color {
        if remainingTime <= 10 {
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

import Foundation
import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
class RecordingViewModel {
    // Services
    let audioService = AudioService()
    let liveTranscriptionService = LiveTranscriptionService()
    let coachingService = HapticCoachingService()

    // State
    var isRecording = false
    var isPaused = false
    var recordingDuration: TimeInterval = 0
    var targetDuration: RecordingDuration = .sixty
    var prompt: Prompt?
    var goalId: UUID?
    var storyId: UUID?

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
    let sentenceSilenceThreshold: TimeInterval = 0.5  // silence gap to consider sentence ended
    let silenceDbThreshold: Float = -40              // dB level below which counts as silence
    let maxGracePeriod: TimeInterval = 10.0           // max extra seconds before force-stop
    var graceStartTime: TimeInterval?

    // Audio level for waveform visualization
    var audioLevel: Float = -160

    // Audio level samples for volume analysis (collected every ~0.5s).
    // @ObservationIgnored: never read by any view — only the view-model
    // itself and SpeechService.analyze consume it. Keeping it observable
    // fires the observation registrar on every 0.5s append for no gain.
    @ObservationIgnored var audioLevelSamples: [Float] = []
    @ObservationIgnored var audioLevelSampleCounter = 0
    var lastCoachingWordCount = 0

    /// Soft cap for `audioLevelSamples` to protect long `.keepGoing` sessions.
    /// 7200 samples = 1 hour at 0.5s cadence. When reached, oldest 1800
    /// (= 15 min) are dropped FIFO so the retained window still represents
    /// the session without unbounded growth.
    static let audioLevelSampleCap = 7200
    static let audioLevelSampleDropChunk = 1800

    // Live filler counter
    var liveFillerCount: Int { liveTranscriptionService.liveFillerCount }

    // Filler word config (set before recording starts)
    var fillerConfig: FillerWordConfig = .default

    // Single 10 Hz timer drives timer progress AND audio-level sampling.
    // Previously two separate timers enqueued 20 main-actor tasks/sec,
    // saturating the main actor and causing coaching-cue animations to
    // stall or crash under load.
    var timer: Timer?
    var modelContext: ModelContext?

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

    // MARK: - Cleanup

    func cleanup() {
        timer?.invalidate()
        timer = nil
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()
        coachingService.reset()
        audioService.cleanup()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

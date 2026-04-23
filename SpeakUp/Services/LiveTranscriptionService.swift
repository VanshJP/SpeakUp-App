import Foundation
import Speech
import AVFoundation

@Observable
class LiveTranscriptionService {
    var liveFillerCount = 0
    var liveWordCount = 0
    var isActive = false
    var fillerConfig: FillerWordConfig = .default

    /// Timestamp (relative to recognition start) when the last spoken word ended.
    /// Used to detect sentence boundaries for graceful recording stop.
    var lastSegmentEndTime: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastProcessedSegmentCount = 0

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Request speech recognition authorization (must be called before start).
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start live transcription using its own audio engine tap.
    /// Call this AFTER the AVAudioRecorder has started so the session is active.
    @MainActor
    func start() {
        guard let recognizer, recognizer.isAvailable else { return }

        // Idempotent: a rapid double-tap on the record button, or a re-entry
        // from the view-model before the previous session has fully torn
        // down, would otherwise install a second tap on a new engine while
        // the old tap is still delivering buffers into a nilled request,
        // crashing AudioToolbox on the next buffer.
        if isActive { stopInternal() }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        liveFillerCount = 0
        liveWordCount = 0
        lastSegmentEndTime = 0
        lastProcessedSegmentCount = 0
        isActive = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Capture the request locally so the real-time audio I/O thread never
        // reaches into main-actor-isolated state. The tap (and this closure's
        // strong reference to `request`) is released by stopInternal()'s
        // removeTap call.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            print("LiveTranscription: audio engine failed to start: \(error)")
            stopInternal()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Hop onto the main actor before touching any state so teardown
            // and partial-result writes never race the 10 Hz recording timer
            // that reads `isActive` / `lastSegmentEndTime`. The recognizer
            // auto-finalizes after an extended pause — running stopInternal
            // on its private queue was tearing down AVAudioEngine off its
            // owning thread and crashing on the next buffer.
            let hadError = error != nil
            let isFinal = result?.isFinal ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result { self.processPartialResult(result) }
                if hadError || isFinal { self.stopInternal() }
            }
        }
    }

    @MainActor
    func stop() {
        recognitionRequest?.endAudio()
        stopInternal()
    }

    @MainActor
    private func stopInternal() {
        // Idempotent: the recognizer's auto-finalization and the view-model's
        // explicit stop() can both fire on the same tick. Tearing the engine
        // down twice was the source of the crash.
        guard isActive else { return }
        isActive = false

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    @MainActor
    private func processPartialResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        let wordCount = segments.count
        guard wordCount > 0 else {
            // Preserve the counter through transient empty partials — the
            // recognizer occasionally emits zero-segment revisions between
            // utterances and we don't want the UI to flash back to 0.
            return
        }

        // Skip reprocessing when the recognizer revises existing segments
        // without adding new words. Post-recording analysis handles precision.
        guard wordCount != lastProcessedSegmentCount else { return }
        lastProcessedSegmentCount = wordCount

        let words = segments.map { $0.substring }
        let timestamps = segments.map { $0.timestamp }
        let durations = segments.map { $0.duration }

        let fillerCount = FillerDetectionPipeline.countFillers(
            words: words,
            timestamps: timestamps,
            durations: durations,
            config: fillerConfig
        )

        let endTime = segments.last.map { $0.timestamp + $0.duration } ?? 0

        // Monotonic during a single recognition session: partial revisions
        // routinely reinterpret a word that was tagged as a filler into a
        // non-filler (or vice versa) once more context arrives. Letting the
        // display regress mid-utterance produces a flicker. Post-recording
        // analysis computes the authoritative count.
        liveFillerCount = max(liveFillerCount, fillerCount)
        liveWordCount = wordCount
        lastSegmentEndTime = endTime
    }
}

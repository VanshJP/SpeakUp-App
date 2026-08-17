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
    /// Cumulative offset so `lastSegmentEndTime` stays monotonic across
    /// recognition restarts (SFSpeech resets timestamps per request).
    private var segmentTimeOffset: TimeInterval = 0
    /// Bumped on every restart/stop so cancelled-task error callbacks cannot
    /// re-enter `restartRecognitionPreservingEngine` in a tight loop.
    private var recognitionGeneration = 0
    /// `removeTap` crashes if no tap is installed — track it explicitly.
    private var isTapInstalled = false
    /// Token only — touched from `deinit` (nonisolated) and init.
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let info = notification.userInfo,
                let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                type == .began
            else { return }
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
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
    ///
    /// Wire input + tap *before* `engine.start()`. Starting an empty graph
    /// while AVAudioRecorder already owns the mic (common on "Start Now"
    /// during countdown) makes `AVAudioEngineGraph::Initialize` raise an
    /// NSException that Swift `do/catch` cannot catch — abort.
    @MainActor
    func start() {
        guard let recognizer, recognizer.isAvailable else { return }

        // Idempotent: a rapid double-tap on the record button, or a re-entry
        // from the view-model before the previous session has fully torn
        // down, would otherwise install a second tap on a new engine while
        // the old tap is still delivering buffers into a nilled request,
        // crashing AudioToolbox on the next buffer. Also clears an engine
        // left running after a failed mid-session recognition re-arm.
        if isActive || audioEngine != nil { stopInternal() }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        liveFillerCount = 0
        liveWordCount = 0
        lastSegmentEndTime = 0
        lastProcessedSegmentCount = 0
        segmentTimeOffset = 0
        isActive = true

        // Touch inputNode so the graph negotiates a hardware format before
        // we start. A 0 Hz format → Initialize exception / silent m4a.
        let session = AVAudioSession.sharedInstance()
        try? session.setPreferredSampleRate(session.sampleRate > 0 ? session.sampleRate : 44_100)
        let inputNode = engine.inputNode
        var format = inputNode.inputFormat(forBus: 0)
        if format.sampleRate <= 0 {
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("LiveTranscription: invalid input format \(format), skipping live fillers")
            stopInternal()
            return
        }

        guard attachRecognition(on: engine) else {
            stopInternal()
            return
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            print("LiveTranscription: audio engine failed to start: \(error)")
            stopInternal()
            return
        }
    }

    @MainActor
    func stop() {
        recognitionRequest?.endAudio()
        stopInternal()
    }

    @MainActor
    private func stopInternal() {
        // Idempotent across explicit stop() + cancelled-task callbacks.
        // Cleanup runs whenever an engine or request is still held — including
        // the orphaned-engine case after a failed recognition re-arm.
        let hasWork = isActive || audioEngine != nil || recognitionRequest != nil
        guard hasWork else { return }

        isActive = false
        recognitionGeneration += 1

        removeTapIfNeeded()
        if let engine = audioEngine {
            engine.stop()
        }
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    @MainActor
    private func removeTapIfNeeded() {
        guard isTapInstalled, let engine = audioEngine else {
            isTapInstalled = false
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    /// Installs a tap + recognition task on an already-running engine.
    /// Returns false when the input format is unusable.
    @MainActor
    @discardableResult
    private func attachRecognition(on engine: AVAudioEngine) -> Bool {
        guard let recognizer, recognizer.isAvailable else { return false }

        let inputNode = engine.inputNode
        // Prefer inputFormat — outputFormat can report 0 Hz before the graph
        // is fully wired even after engine.start().
        var format = inputNode.inputFormat(forBus: 0)
        if format.sampleRate <= 0 {
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("LiveTranscription: invalid input format \(format), skipping tap")
            return false
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Unconditional: on-device processing is a product guarantee, not a
        // preference, and `supportsOnDeviceRecognition` can read false while
        // assets are still installing — which used to hand that session's
        // microphone audio to Apple's servers. It also keeps latency low and
        // avoids network pauses that force early isFinal → restart cycles.
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request
        lastProcessedSegmentCount = 0
        recognitionGeneration += 1
        let generation = recognitionGeneration

        removeTapIfNeeded()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        isTapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Hop onto the main actor before touching any state so teardown
            // and partial-result writes never race the 10 Hz recording timer
            // that reads `isActive` / `lastSegmentEndTime`.
            let hadError = error != nil
            let isFinal = result?.isFinal ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Ignore callbacks from cancelled generations (restart/stop).
                guard self.isActive, self.recognitionGeneration == generation else { return }
                if let result { self.processPartialResult(result) }

                // SFSpeech auto-finalizes after a pause. Previously we tore
                // down AVAudioEngine here, which yanked the shared input graph
                // out from under AVAudioRecorder mid-take and left the rest of
                // the m4a silent — Whisper then scored the session as Silent.
                // Keep the engine running and open a fresh recognition request.
                if hadError || isFinal {
                    self.restartRecognitionPreservingEngine()
                }
            }
        }
        return true
    }

    /// Re-arms speech recognition without stopping AVAudioEngine, so the
    /// concurrent AVAudioRecorder keeps a stable mic route.
    @MainActor
    private func restartRecognitionPreservingEngine() {
        guard isActive, let engine = audioEngine else {
            stopInternal()
            return
        }

        // Carry forward the furthest end time so sentence-boundary detection
        // still works across request boundaries.
        segmentTimeOffset = max(segmentTimeOffset, lastSegmentEndTime)

        // Invalidate in-flight callbacks before cancelling so the cancel error
        // cannot recurse into another restart.
        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        removeTapIfNeeded()

        guard attachRecognition(on: engine) else {
            // Leave the audio graph alone for AVAudioRecorder — only drop
            // live-transcription state so metering / capture keep working.
            isActive = false
            recognitionTask = nil
            recognitionRequest = nil
            return
        }
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
        liveWordCount = max(liveWordCount, wordCount)
        lastSegmentEndTime = max(lastSegmentEndTime, segmentTimeOffset + endTime)
    }
}

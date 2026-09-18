import Foundation
import os.log
import Speech
import AVFoundation
import os

/// Real-time speech recognition service using Apple Speech framework.
/// Extracts individual words for the word bank via on-device recognition.
@Observable
@MainActor
class DictationService {
    private let logger = Logger.app("Dictation")
    var isListening = false
    var recognizedWords: [String] = []
    var lastAddedIndex = 0

    /// Why the last `start()` gave up, for the caller to display. Every failure
    /// path here is silent otherwise - the mic button simply never lights up.
    var errorMessage: String?

    /// Current audio input level in dB (-160 silence … 0 max).
    var audioLevel: Float = -160

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    /// Read from the realtime audio thread by the tap block and torn down on
    /// the main actor, so it cannot be plain isolated state. The critical
    /// section is one `append`; nilling it from `cleanup()` while the tap was
    /// mid-append segfaulted exactly like LiveTranscriptionService's war story.
    private let requestBox = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(uncheckedState: nil)
    private var recognitionTask: SFSpeechRecognitionTask?

    /// `removeTap` crashes if no tap is installed - track it explicitly.
    private var isTapInstalled = false

    /// Thread-safe storage for the latest RMS level computed in the audio tap callback.
    private let levelStorage = AudioLevelStorage()

    /// Timer that reads the latest level from the tap callback and publishes to `audioLevel`.
    private var levelTimer: Timer?

    /// Set while `stop()` tears the session down, so the cancellation error the
    /// recognizer reports back is not mistaken for a real failure.
    private var isStopping = false

    /// Bumped on every `start` / `stop` so a cancelled session's recognition
    /// callback cannot `cleanup()` the replacement session.
    private var sessionGeneration = 0

    /// Words collected by the requests that have already been retired. Each
    /// new request's transcript starts empty and `processResult` publishes the
    /// whole list, so without this prefix a single pause would wipe everything
    /// the user had dictated so far.
    private var committedWords: [String] = []

    /// When the live request was opened, and how many have died instantly with
    /// nothing to show for it. A recognizer missing its on-device assets fails
    /// that way immediately and forever; re-arming it in a tight loop would
    /// spin the CPU behind a mic button that looks live.
    private var segmentStartedAt = Date.distantPast
    private var unproductiveSegments = 0
    private static let unproductiveSegmentWindow: TimeInterval = 1.0
    private static let maxUnproductiveSegments = 3

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Public API

    func start() async {
        // Idempotent: a second tap before `isListening` flips used to install
        // another tap on a live engine (audio-thread fault class).
        if isListening || audioEngine != nil {
            stop()
        }

        sessionGeneration += 1
        let generation = sessionGeneration

        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard generation == sessionGeneration else { return }
        guard authorized else {
            errorMessage = "Speech recognition permission is off. Turn it on in Settings."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        recognizedWords = []
        committedWords = []
        unproductiveSegments = 0
        lastAddedIndex = 0
        audioLevel = -160
        errorMessage = nil
        isStopping = false

        let engine = AVAudioEngine()
        self.audioEngine = engine

        do {
            // Off the main actor: `setActive` blocks until the audio server has
            // the session up, and the console has been warning about that stall
            // on every mic tap ("can lead to UI unresponsiveness").
            try await Task.detached(priority: .userInitiated) {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            }.value
        } catch {
            logger.error("DictationService: audio session setup failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            errorMessage = "Couldn't start the microphone."
            return
        }

        let inputNode = engine.inputNode
        // Prefer inputFormat; outputFormat can report 0 Hz before the graph
        // is wired - starting then raises an uncaught NSException.
        var recordingFormat = inputNode.inputFormat(forBus: 0)
        if recordingFormat.sampleRate <= 0 {
            recordingFormat = inputNode.outputFormat(forBus: 0)
        }
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            logger.error("DictationService: invalid input format \(String(describing: recordingFormat), privacy: .public)")
            errorMessage = "Couldn't start the microphone."
            cleanup()
            return
        }
        let storage = self.levelStorage

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [requestBox, storage] buffer, _ in
            requestBox.withLock { $0?.append(buffer) }

            // Compute RMS from buffer for audio level visualization
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sumOfSquares: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sumOfSquares += sample * sample
            }
            let rms = sqrt(sumOfSquares / Float(frameCount))
            let db = 20 * log10(max(rms, 1e-10))
            storage.set(db)
        }
        isTapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            logger.error("DictationService: audio engine failed to start: \(error.localizedDescription, privacy: .private(mask: .hash))")
            errorMessage = "Couldn't start the microphone."
            cleanup()
            return
        }

        guard generation == sessionGeneration else {
            cleanup()
            return
        }

        isListening = true

        // Poll the level storage on the main thread for UI updates
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.sessionGeneration == generation else { return }
                self.audioLevel = storage.get()
            }
        }

        armRecognition(generation: generation)
    }

    /// Opens a recognition request on the already-running engine and points the
    /// tap at it.
    ///
    /// Re-arming swaps the request inside `requestBox` and leaves the tap
    /// alone: re-installing a tap on a live engine reconfigures AURemoteIO
    /// under its own IO thread (gotcha §9). The retired request is flushed
    /// rather than cancelled, so its last words still arrive.
    ///
    /// - Parameter flushRetired: false when the retired request has already
    ///   finished on its own - `endAudio()` must not be called twice on one
    ///   request.
    private func armRecognition(generation: Int, flushRetired: Bool = true) {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            cleanup()
            isListening = false
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Unconditional: on-device processing is a product guarantee, not a
        // preference. Left unset, the recognizer is free to stream microphone
        // audio to Apple's servers. If the on-device assets are not available
        // the request fails, and failing is the correct outcome here.
        request.requiresOnDeviceRecognition = true

        let retired = requestBox.withLock { box -> SFSpeechAudioBufferRecognitionRequest? in
            let previous = box
            box = request
            return previous
        }
        if flushRetired { retired?.endAudio() }

        segmentStartedAt = Date()
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    guard self.sessionGeneration == generation else { return }
                    self.processResult(result)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                let hadError = error != nil
                Task { @MainActor in
                    guard self.sessionGeneration == generation else { return }
                    self.handleRecognitionEnd(generation: generation, hadError: hadError)
                }
            }
        }
    }

    /// A recognition request ended. For dictation that is routine rather than
    /// fatal: SFSpeech finalizes after a pause in speech, and someone picking
    /// words out of their head pauses constantly. This used to tear the whole
    /// session down, so the mic button went dark mid-thought and every word
    /// after the pause was lost. Re-arm on the same engine instead.
    private func handleRecognitionEnd(generation: Int, hadError: Bool) {
        // `stop()` cancels the task, which reports an error too - only an
        // unrequested failure is worth telling the user about.
        guard !isStopping else {
            cleanup()
            isListening = false
            return
        }
        guard isListening else { return }

        let grew = recognizedWords.count > committedWords.count
        let lifetime = Date().timeIntervalSince(segmentStartedAt)
        committedWords = recognizedWords
        if grew || lifetime >= Self.unproductiveSegmentWindow {
            unproductiveSegments = 0
        } else {
            unproductiveSegments += 1
        }

        let engineIsLive = audioEngine?.isRunning == true
        guard engineIsLive, unproductiveSegments < Self.maxUnproductiveSegments else {
            // On-device recognition is required, so a device whose assets are
            // missing lands here rather than sending the audio to a server.
            if hadError {
                errorMessage = "On-device dictation isn't ready yet. Try again in a moment."
            }
            cleanup()
            isListening = false
            return
        }

        // The request that just ended has already flushed itself.
        armRecognition(generation: generation, flushRetired: false)
    }

    func stop() {
        sessionGeneration += 1
        isStopping = true
        requestBox.withLock { $0?.endAudio() }
        cleanup()
        isListening = false
    }

    // MARK: - Result Processing

    private func processResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        let words = segments.map { $0.substring }
            .filter { $0.count >= 2 }
            .map { $0.capitalized }

        var seen = Set<String>()
        var unique: [String] = []
        // `committedWords` first: the live request's transcript restarts at
        // empty on every re-arm, so the prefix is what keeps a pause from
        // wiping the list the user is building.
        for word in committedWords + words {
            let key = word.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(word)
            }
        }
        recognizedWords = unique
    }

    // MARK: - Cleanup

    private func cleanup() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = -160

        audioEngine?.stop()
        if isTapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.withLock { $0 = nil }
    }
}

// MARK: - Thread-Safe Audio Level Storage

/// Lock-free atomic float storage for passing audio levels from the audio tap (real-time thread)
/// to the main thread without blocking.
private final class AudioLevelStorage: @unchecked Sendable {
    private let _value = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    init() { _value.initialize(to: -160) }
    deinit { _value.deallocate() }

    func set(_ value: Float) {
        _value.pointee = value
    }

    func get() -> Float {
        _value.pointee
    }
}

import Foundation
import Speech
import AVFoundation
import os

/// Real-time speech recognition service using Apple Speech framework.
/// Extracts individual words for the word bank via on-device recognition.
@Observable
@MainActor
class DictationService {
    var isListening = false
    var recognizedWords: [String] = []
    var lastAddedIndex = 0

    /// Why the last `start()` gave up, for the caller to display. Every failure
    /// path here is silent otherwise — the mic button simply never lights up.
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

    /// `removeTap` crashes if no tap is installed — track it explicitly.
    private var isTapInstalled = false

    /// Thread-safe storage for the latest RMS level computed in the audio tap callback.
    private let levelStorage = AudioLevelStorage()

    /// Timer that reads the latest level from the tap callback and publishes to `audioLevel`.
    private var levelTimer: Timer?

    /// Set while `stop()` tears the session down, so the cancellation error the
    /// recognizer reports back is not mistaken for a real failure.
    private var isStopping = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Public API

    func start() async {
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else {
            errorMessage = "Speech recognition permission is off. Turn it on in Settings."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        recognizedWords = []
        lastAddedIndex = 0
        audioLevel = -160
        errorMessage = nil
        isStopping = false

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("DictationService: audio session setup failed: \(error)")
            errorMessage = "Couldn't start the microphone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Unconditional: on-device processing is a product guarantee, not a
        // preference. Left unset, the recognizer is free to stream microphone
        // audio to Apple's servers. If the on-device assets are not available
        // the request fails, and failing is the correct outcome here.
        request.requiresOnDeviceRecognition = true
        requestBox.withLock { $0 = request }

        let inputNode = engine.inputNode
        // Prefer inputFormat; outputFormat can report 0 Hz before the graph
        // is wired — starting then raises an uncaught NSException.
        var recordingFormat = inputNode.inputFormat(forBus: 0)
        if recordingFormat.sampleRate <= 0 {
            recordingFormat = inputNode.outputFormat(forBus: 0)
        }
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("DictationService: invalid input format \(recordingFormat)")
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
            print("DictationService: audio engine failed to start: \(error)")
            errorMessage = "Couldn't start the microphone."
            cleanup()
            return
        }

        isListening = true

        // Poll the level storage on the main thread for UI updates
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.audioLevel = storage.get()
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    self.processResult(result)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    // `stop()` cancels the task, which reports an error too —
                    // only an unrequested failure is worth telling the user
                    // about. On-device recognition is required, so a device
                    // whose assets are missing lands here rather than sending
                    // the audio to a server.
                    if error != nil, !self.isStopping {
                        self.errorMessage = "On-device dictation isn't ready yet. Try again in a moment."
                    }
                    self.cleanup()
                    self.isListening = false
                }
            }
        }
    }

    func stop() {
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
        for word in words {
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

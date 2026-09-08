import Foundation
import os.log
import Speech
import AVFoundation
import os

@Observable
@MainActor
class DictationService {
    private let logger = Logger.app("Dictation")
    var isListening = false
    var recognizedWords: [String] = []
    var lastAddedIndex = 0

    /// Why the last `start()` gave up, for the caller to display. Every failure
    /// path here is silent otherwise — the mic button simply never lights up.
    var errorMessage: String?

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

    private var levelTimer: Timer?

    private var isStopping = false

    private var sessionGeneration = 0

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
            logger.error("DictationService: audio session setup failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
            errorMessage = "Couldn't start the microphone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        requestBox.withLock { $0 = request }

        let inputNode = engine.inputNode
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

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.sessionGeneration == generation else { return }
                self.audioLevel = storage.get()
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    guard self.sessionGeneration == generation else { return }
                    self.processResult(result)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    guard self.sessionGeneration == generation else { return }
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

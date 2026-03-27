import Foundation
import Speech
import AVFoundation

/// Real-time speech recognition service using Apple Speech framework.
/// Extracts individual words for the word bank via on-device recognition.
@Observable
@MainActor
class DictationService {
    var isListening = false
    var recognizedWords: [String] = []
    var lastAddedIndex = 0

    /// Current audio input level in dB (-160 silence … 0 max).
    var audioLevel: Float = -160

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Thread-safe storage for the latest RMS level computed in the audio tap callback.
    private let levelStorage = AudioLevelStorage()

    /// Timer that reads the latest level from the tap callback and publishes to `audioLevel`.
    private var levelTimer: Timer?

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
        guard authorized else { return }
        guard let recognizer, recognizer.isAvailable else { return }

        recognizedWords = []
        lastAddedIndex = 0
        audioLevel = -160

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("DictationService: audio session setup failed: \(error)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let storage = self.levelStorage

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

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

        do {
            try engine.start()
        } catch {
            print("DictationService: audio engine failed to start: \(error)")
            cleanup()
            return
        }

        isListening = true

        // Poll the level storage on the main thread for UI updates
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.audioLevel = storage.get()
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
                    self.cleanup()
                    self.isListening = false
                }
            }
        }
    }

    func stop() {
        recognitionRequest?.endAudio()
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
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
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

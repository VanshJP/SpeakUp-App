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
    func start() {
        guard let recognizer, recognizer.isAvailable else { return }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        liveFillerCount = 0
        liveWordCount = 0
        lastSegmentEndTime = 0
        isActive = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            print("LiveTranscription: audio engine failed to start: \(error)")
            stopInternal()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.processPartialResult(result)
            }

            if error != nil || (result?.isFinal ?? false) {
                self.stopInternal()
            }
        }
    }

    func stop() {
        recognitionRequest?.endAudio()
        stopInternal()
    }

    private func stopInternal() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isActive = false
    }

    private func processPartialResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        let wordCount = segments.count
        let lastEndTime = segments.last.map { $0.timestamp + $0.duration }

        guard wordCount > 0 else {
            Task { @MainActor in
                if self.liveFillerCount != 0 {
                    self.liveFillerCount = 0
                }
                if self.liveWordCount != 0 {
                    self.liveWordCount = 0
                }
                if self.lastSegmentEndTime != 0 {
                    self.lastSegmentEndTime = 0
                }
            }
            return
        }

        let words = segments.map { $0.substring }
        let timestamps = segments.map { $0.timestamp }
        let durations = segments.map { $0.duration }

        let fillerCount = FillerDetectionPipeline.countFillers(
            words: words,
            timestamps: timestamps,
            durations: durations,
            config: fillerConfig
        )

        Task { @MainActor in
            if self.liveFillerCount != fillerCount {
                self.liveFillerCount = fillerCount
            }
            if self.liveWordCount != wordCount {
                self.liveWordCount = wordCount
            }
            if let lastEndTime, abs(self.lastSegmentEndTime - lastEndTime) > 0.01 {
                self.lastSegmentEndTime = lastEndTime
            }
        }
    }
}

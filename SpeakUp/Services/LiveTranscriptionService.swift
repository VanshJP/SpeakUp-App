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

    /// Monotonic clock time when recognition started, used to convert
    /// segment timestamps into elapsed-recording time.
    private var recognitionStartTime: CFAbsoluteTime = 0

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
        recognitionStartTime = CFAbsoluteTimeGetCurrent()
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
        guard wordCount > 0 else {
            Task { @MainActor in
                self.liveFillerCount = 0
                self.liveWordCount = 0
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

        // Track when the last word ended (segment timestamp + duration)
        if let lastSegment = segments.last {
            let endTime = lastSegment.timestamp + lastSegment.duration
            Task { @MainActor in
                self.lastSegmentEndTime = endTime
            }
        }

        Task { @MainActor in
            self.liveFillerCount = fillerCount
            self.liveWordCount = wordCount
        }
    }
}

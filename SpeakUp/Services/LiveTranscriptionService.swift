import Foundation
import Speech
import AVFoundation

@Observable
class LiveTranscriptionService {
    var liveFillerCount = 0
    var isActive = false

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
        // Each partial result contains ALL segments so far — just count fillers across all of them.
        let count = result.bestTranscription.segments.reduce(0) { total, segment in
            total + (FillerWordList.isFillerWord(segment.substring) ? 1 : 0)
        }

        Task { @MainActor in
            self.liveFillerCount = count
        }
    }
}

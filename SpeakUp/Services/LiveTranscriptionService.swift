import Foundation
import Speech
import AVFoundation

@Observable
class LiveTranscriptionService {
    var liveFillerCount = 0
    var liveWordCount = 0
    var isActive = false

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

        let pauseThreshold: TimeInterval = 0.3
        var fillerCount = 0
        var fillerIndices = Set<Int>()

        for (i, segment) in segments.enumerated() {
            let word = segment.substring
            let prev = i > 0 ? segments[i - 1].substring : nil
            let next = i < segments.count - 1 ? segments[i + 1].substring : nil

            // Pause before: gap between previous segment end and this segment start
            let pauseBefore: Bool
            if i == 0 {
                pauseBefore = segment.timestamp > pauseThreshold
            } else {
                let prevEnd = segments[i - 1].timestamp + segments[i - 1].duration
                pauseBefore = (segment.timestamp - prevEnd) > pauseThreshold
            }

            // Pause after: gap between this segment end and next segment start
            let pauseAfter: Bool
            if i == segments.count - 1 {
                pauseAfter = true
            } else {
                let thisEnd = segment.timestamp + segment.duration
                pauseAfter = (segments[i + 1].timestamp - thisEnd) > pauseThreshold
            }

            // Sentence boundary: long pause from previous word
            let isStartOfSentence: Bool
            if i == 0 {
                isStartOfSentence = true
            } else {
                let prevEnd = segments[i - 1].timestamp + segments[i - 1].duration
                isStartOfSentence = (segment.timestamp - prevEnd) > 0.8
            }

            if FillerWordList.isFillerWord(
                word,
                previousWord: prev,
                nextWord: next,
                pauseBefore: pauseBefore,
                pauseAfter: pauseAfter,
                isStartOfSentence: isStartOfSentence
            ) {
                fillerIndices.insert(i)
            }
        }

        // Second pass: detect multi-word filler phrases ("you know", "I mean", etc.)
        if segments.count >= 2 {
            for i in 0..<(segments.count - 1) {
                if FillerWordList.isFillerPhrase(segments[i].substring, segments[i + 1].substring) {
                    fillerIndices.insert(i)
                    fillerIndices.insert(i + 1)
                }
            }
        }

        fillerCount = fillerIndices.count

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

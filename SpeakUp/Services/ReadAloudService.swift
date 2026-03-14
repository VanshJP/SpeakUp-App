import Foundation
import Speech
import AVFoundation

// MARK: - Word Match State

enum WordMatchState: Equatable {
    case upcoming
    case current
    case matched
    case mismatched(spoken: String)
    case skipped
}

// MARK: - Read Aloud Error

enum ReadAloudError: LocalizedError {
    case speechNotAvailable
    case authorizationDenied
    case audioEngineFailure(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechNotAvailable:
            return "Speech recognition is not available on this device."
        case .authorizationDenied:
            return "Speech recognition permission was denied. Enable it in Settings."
        case .audioEngineFailure(let detail):
            return "Audio engine failed: \(detail)"
        case .recognitionFailed(let detail):
            return "Recognition failed: \(detail)"
        }
    }
}

// MARK: - Read Aloud Service

@Observable
class ReadAloudService {
    var wordStates: [WordMatchState] = []
    var currentWordIndex: Int = 0
    var matchedWordCount: Int = 0
    var mismatchedWordCount: Int = 0
    var isListening = false
    var errorMessage: String?

    private var referenceWords: [String] = []
    private var normalizedReference: [String] = []

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Tracks the last processed segment count to avoid reprocessing.
    private var lastProcessedSegmentCount = 0

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Configure

    func configure(passage: ReadAloudPassage) {
        referenceWords = passage.words
        normalizedReference = referenceWords.map { Self.normalize($0) }
        wordStates = Array(repeating: .upcoming, count: referenceWords.count)
        currentWordIndex = 0
        matchedWordCount = 0
        mismatchedWordCount = 0
        lastProcessedSegmentCount = 0
        errorMessage = nil
    }

    // MARK: - Start Listening

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ReadAloudError.speechNotAvailable
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            stopInternal()
            throw ReadAloudError.audioEngineFailure(error.localizedDescription)
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.processResult(result)
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.isListening = false
                }
            }
        }
    }

    // MARK: - Stop

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
        isListening = false
    }

    // MARK: - Process Recognition Result

    private func processResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        let segmentCount = segments.count
        guard segmentCount > lastProcessedSegmentCount else { return }

        // Process only new segments since last update
        let newSegments = Array(segments[lastProcessedSegmentCount...])
        lastProcessedSegmentCount = segmentCount

        Task { @MainActor in
            for segment in newSegments {
                guard self.currentWordIndex < self.referenceWords.count else { break }

                let spokenNorm = Self.normalize(segment.substring)
                let expectedNorm = self.normalizedReference[self.currentWordIndex]

                if spokenNorm == expectedNorm {
                    self.wordStates[self.currentWordIndex] = .matched
                    self.matchedWordCount += 1
                    self.currentWordIndex += 1
                } else {
                    // Check if the spoken word matches a word slightly ahead (user skipped a word)
                    let lookAhead = min(self.currentWordIndex + 3, self.referenceWords.count)
                    var foundAhead = false

                    for i in (self.currentWordIndex + 1)..<lookAhead {
                        if spokenNorm == self.normalizedReference[i] {
                            // Mark skipped words
                            for j in self.currentWordIndex..<i {
                                self.wordStates[j] = .skipped
                                self.mismatchedWordCount += 1
                            }
                            self.wordStates[i] = .matched
                            self.matchedWordCount += 1
                            self.currentWordIndex = i + 1
                            foundAhead = true
                            break
                        }
                    }

                    if !foundAhead {
                        self.wordStates[self.currentWordIndex] = .mismatched(spoken: segment.substring)
                        self.mismatchedWordCount += 1
                        self.currentWordIndex += 1
                    }
                }
            }

            // Mark current word
            if self.currentWordIndex < self.wordStates.count {
                // Only set current if it's still upcoming
                if self.wordStates[self.currentWordIndex] == .upcoming {
                    self.wordStates[self.currentWordIndex] = .current
                }
            }

            // Check if passage is complete
            if self.currentWordIndex >= self.referenceWords.count {
                self.stop()
            }
        }
    }

    // MARK: - Scoring

    var accuracyPercentage: Double {
        let total = matchedWordCount + mismatchedWordCount
        guard total > 0 else { return 0 }
        return (Double(matchedWordCount) / Double(total)) * 100
    }

    var progressPercentage: Double {
        guard !referenceWords.isEmpty else { return 0 }
        return Double(currentWordIndex) / Double(referenceWords.count)
    }

    var isComplete: Bool {
        currentWordIndex >= referenceWords.count
    }

    // MARK: - Helpers

    static func normalize(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

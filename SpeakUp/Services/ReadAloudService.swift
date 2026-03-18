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

    private var referenceWords: [String] = []
    private var normalizedReference: [String] = []
    private var lastProcessedTranscript: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?


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
        lastProcessedTranscript = ""
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
        // Use formattedString split into words instead of segments.
        // Segments can split words mid-utterance in partial results (e.g. "quantum"
        // appears as segment "quant" then later corrects). formattedString gives the
        // recognizer's best word-boundary output, and re-evaluating on every callback
        // lets earlier partial mis-splits self-correct as more audio arrives.
        let transcript = result.bestTranscription.formattedString
        guard transcript != lastProcessedTranscript else { return }
        lastProcessedTranscript = transcript

        let spokenWords = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let computed = computeWordStates(from: spokenWords)

        Task { @MainActor in
            if self.wordStates != computed.states {
                self.wordStates = computed.states
            }
            if self.currentWordIndex != computed.refIndex {
                self.currentWordIndex = computed.refIndex
            }
            if self.matchedWordCount != computed.matched {
                self.matchedWordCount = computed.matched
            }
            if self.mismatchedWordCount != computed.mismatched {
                self.mismatchedWordCount = computed.mismatched
            }

            // Check if passage is complete
            if computed.refIndex >= self.referenceWords.count {
                self.stop()
            }
        }
    }

    private func computeWordStates(from spokenWords: [String]) -> (states: [WordMatchState], refIndex: Int, matched: Int, mismatched: Int) {
        var newStates = Array(repeating: WordMatchState.upcoming, count: referenceWords.count)
        var refIndex = 0
        var matched = 0
        var mismatched = 0

        for spokenWord in spokenWords {
            guard refIndex < referenceWords.count else { break }

            let spokenNorm = Self.normalize(spokenWord)
            let expectedNorm = normalizedReference[refIndex]

            if spokenNorm == expectedNorm {
                newStates[refIndex] = .matched
                matched += 1
                refIndex += 1
            } else {
                let lookAhead = min(refIndex + 3, referenceWords.count)
                var foundAhead = false

                if lookAhead > refIndex + 1 {
                    for i in (refIndex + 1)..<lookAhead {
                        if spokenNorm == normalizedReference[i] {
                            for j in refIndex..<i {
                                newStates[j] = .skipped
                                mismatched += 1
                            }
                            newStates[i] = .matched
                            matched += 1
                            refIndex = i + 1
                            foundAhead = true
                            break
                        }
                    }
                }

                if !foundAhead {
                    newStates[refIndex] = .mismatched(spoken: spokenWord)
                    mismatched += 1
                    refIndex += 1
                }
            }
        }

        if refIndex < newStates.count {
            newStates[refIndex] = .current
        }

        return (newStates, refIndex, matched, mismatched)
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
        let lowered = word
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")

        return lowered
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

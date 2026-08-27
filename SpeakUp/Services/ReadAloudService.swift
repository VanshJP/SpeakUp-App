import Foundation
import Speech
import AVFoundation
import os

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

    /// Set when the recognizer dies mid-session (missing on-device assets,
    /// engine loss). The view model surfaces this as a result notice instead
    /// of letting the session end in a confident-looking zero.
    var recognitionFailureMessage: String?

    private var referenceWords: [String] = []
    private var normalizedReference: [String] = []
    private var lastProcessedTranscript: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    /// Read from the realtime audio thread by the tap block and torn down on
    /// the main actor, so it cannot be plain isolated state. The critical
    /// section is one `append`; nilling it from `stopInternal()` while the tap
    /// was mid-append segfaulted exactly like LiveTranscriptionService's war story.
    private let requestBox = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(uncheckedState: nil)
    private var recognitionTask: SFSpeechRecognitionTask?

    /// `removeTap` crashes if no tap is installed — track it explicitly.
    private var isTapInstalled = false


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
        recognitionFailureMessage = nil
    }

    // MARK: - Start Listening

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ReadAloudError.speechNotAvailable
        }

        // Idempotent, same rule as LiveTranscriptionService: a Retry racing a
        // ghost start must not stack a second engine and tap on top of the
        // first — tear the old graph down before building a new one.
        if audioEngine != nil || isTapInstalled || recognitionTask != nil {
            stopInternal()
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Unconditional: on-device processing is a product guarantee, not a
        // preference. Left unset, the recognizer is free to stream microphone
        // audio to Apple's servers. If the on-device assets are not available
        // the request fails, and failing is the correct outcome here.
        request.requiresOnDeviceRecognition = true
        requestBox.withLock { $0 = request }

        let inputNode = engine.inputNode
        var recordingFormat = inputNode.inputFormat(forBus: 0)
        if recordingFormat.sampleRate <= 0 {
            recordingFormat = inputNode.outputFormat(forBus: 0)
        }
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            stopInternal()
            throw ReadAloudError.audioEngineFailure("Invalid microphone format \(recordingFormat)")
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [requestBox] buffer, _ in
            requestBox.withLock { $0?.append(buffer) }
        }
        isTapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            stopInternal()
            throw ReadAloudError.audioEngineFailure(error.localizedDescription)
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                // Apple fires this callback on an internal queue; hop to the
                // main actor before processResult touches observable state.
                Task { @MainActor in
                    self.processResult(result)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    // A dead recognizer must not leave the engine running with
                    // a hot mic behind a "Not listening" label — and it must
                    // not end as a silent zero either. Full teardown here, and
                    // the message travels out via recognitionFailureMessage.
                    if let error, self.recognitionFailureMessage == nil {
                        self.recognitionFailureMessage =
                            ReadAloudError.recognitionFailed(error.localizedDescription).errorDescription
                    }
                    self.stopInternal()
                }
            }
        }
    }

    // MARK: - Stop

    func stop() {
        requestBox.withLock { $0?.endAudio() }
        stopInternal()
    }

    private func stopInternal() {
        audioEngine?.stop()
        if isTapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        requestBox.withLock { $0 = nil }
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
        Self.computeAlignment(
            reference: referenceWords,
            normalizedReference: normalizedReference,
            spokenWords: spokenWords
        )
    }

    /// Pure alignment core, static and nonisolated so unit tests can pin its
    /// behavior directly (default isolation would otherwise fence it behind
    /// the main actor).
    ///
    /// Greedy left-to-right match. Handles the two ways real reading drifts
    /// from the page:
    /// - **Skipped words** (reader drops a word): a spoken word that matches a
    ///   nearby *reference* word marks everything between as `.skipped`.
    /// - **Inserted words** (filler, stumble): a spoken word matching nothing
    ///   is checked against what the *next* spoken word resolves to — if that
    ///   lands on the current or an upcoming reference word, the first word
    ///   was an insertion, not a miss. Single-word lookahead keeps skip vs
    ///   insert deterministic; deeper stumbles re-sync on the next partial
    ///   result anyway.
    nonisolated static func computeAlignment(
        reference: [String],
        normalizedReference: [String],
        spokenWords: [String]
    ) -> (states: [WordMatchState], refIndex: Int, matched: Int, mismatched: Int) {
        var newStates = Array(repeating: WordMatchState.upcoming, count: reference.count)
        var refIndex = 0
        var matched = 0
        var mismatched = 0

        func markSkipped(_ range: Range<Int>) {
            for j in range {
                newStates[j] = .skipped
                mismatched += 1
            }
        }

        var spokenIndex = 0
        while spokenIndex < spokenWords.count {
            guard refIndex < reference.count else { break }

            let spokenNorm = normalize(spokenWords[spokenIndex])
            let expectedNorm = normalizedReference[refIndex]

            if spokenNorm == expectedNorm {
                newStates[refIndex] = .matched
                matched += 1
                refIndex += 1
                spokenIndex += 1
                continue
            }

            // Skipped-reference path: this spoken word belongs further ahead
            // in the passage.
            let lookAhead = min(refIndex + 3, reference.count)
            var foundAhead = false

            if lookAhead > refIndex + 1 {
                for i in (refIndex + 1)..<lookAhead where spokenNorm == normalizedReference[i] {
                    markSkipped(refIndex..<i)
                    newStates[i] = .matched
                    matched += 1
                    refIndex = i + 1
                    foundAhead = true
                    break
                }
            }
            if foundAhead {
                spokenIndex += 1
                continue
            }

            // Insertion path: if the NEXT spoken word resolves at or near the
            // current position, this word was said in passing ("um") — drop it
            // without consuming a reference word or counting a miss.
            let nextIndex = spokenIndex + 1
            if nextIndex < spokenWords.count {
                let nextNorm = normalize(spokenWords[nextIndex])
                let nextResolvesHere = !nextNorm.isEmpty && nextNorm == expectedNorm
                let nextResolvesAhead = normalizedReference[(refIndex + 1)..<lookAhead]
                    .contains { $0 == nextNorm }
                if nextResolvesHere || nextResolvesAhead {
                    spokenIndex += 1
                    continue
                }
            }

            newStates[refIndex] = .mismatched(spoken: spokenWords[spokenIndex])
            mismatched += 1
            refIndex += 1
            spokenIndex += 1
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

    /// Canonical form used for matching. Case, curly apostrophes, hyphens,
    /// and punctuation all fold away — and spelled numbers collapse to digits,
    /// because the page says "seventy-two" while the recognizer writes "72".
    nonisolated static func normalize(_ word: String) -> String {
        let lowered = word
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")

        let stripped = lowered
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Self.spelledNumberValue(stripped) ?? stripped
    }

    /// Parses tokens composed entirely of number words to their digit string.
    /// Handles both spaced ("one hundred") and fused ("onehundred",
    /// "seventytwo" — hyphens were stripped upstream) forms by greedily
    /// consuming the longest number-word prefix at each step. Returns nil for
    /// anything containing a non-number word — including plain digits, which
    /// are already canonical.
    private nonisolated static func spelledNumberValue(_ token: String) -> String? {
        guard !token.isEmpty, token.contains(where: \.isLetter) else { return nil }

        let lexicon: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
            "fourteen": 14, "fifteen": 15, "sixteen": 16,
            "seventeen": 17, "eighteen": 18, "nineteen": 19,
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
            "hundred": 0, "thousand": 0, "and": 0
        ]
        let scaleMarkers: Set<String> = ["hundred", "thousand"]
        let sortedWords = lexicon.keys.sorted { $0.count > $1.count }

        var parts: [String] = []
        var rest = Substring(token)
        while !rest.isEmpty {
            if rest.first == " " {
                rest = rest.dropFirst()
                continue
            }
            guard let match = sortedWords.first(where: { rest.hasPrefix($0) }) else {
                return nil
            }
            parts.append(match)
            rest = rest.dropFirst(match.count)
        }

        var total = 0
        var current = 0
        var sawNumberWord = false

        for part in parts where part != "and" {
            if let value = lexicon[part], !scaleMarkers.contains(part) {
                current += value
                sawNumberWord = true
            } else if part == "hundred" {
                current = max(current, 1) * 100
                sawNumberWord = true
            } else if part == "thousand" {
                total += max(current, 1) * 1000
                current = 0
                sawNumberWord = true
            }
        }

        guard sawNumberWord else { return nil }
        return String(total + current)
    }
}

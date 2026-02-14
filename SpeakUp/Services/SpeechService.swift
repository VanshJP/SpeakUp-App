import Foundation
import Speech
import AVFoundation

@Observable
class SpeechService {
    // State
    var isTranscribing = false
    var hasPermission = false
    var transcriptionProgress: Double = 0
    var modelLoadProgress: Double = 0
    var isModelLoaded: Bool { whisperService.isModelLoaded }

    // Transcription backend
    private let whisperService = WhisperService()

    // Fallback: Apple Speech recognizer (for when WhisperKit fails)
    private let recognizer: SFSpeechRecognizer?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Model Loading

    /// Pre-load the Whisper model (call on app launch for better UX)
    func preloadModel() async {
        await whisperService.loadModel(modelVariant: "base")
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        // For WhisperKit, we only need microphone permission (handled by AudioService)
        // Keep this for backward compatibility
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        hasPermission = status == .authorized
        return hasPermission
    }

    var permissionStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL) async throws -> SpeechTranscriptionResult {
        isTranscribing = true
        transcriptionProgress = 0

        defer {
            isTranscribing = false
            transcriptionProgress = 1.0
        }

        do {
            // Use WhisperKit for accurate filler word detection
            let result = try await whisperService.transcribe(audioURL: audioURL)
            transcriptionProgress = whisperService.transcriptionProgress
            return result
        } catch {
            // Fallback to Apple Speech if WhisperKit fails
            print("WhisperKit failed, falling back to Apple Speech: \(error)")
            return try await transcribeWithAppleSpeech(audioURL: audioURL)
        }
    }

    /// Fallback transcription using Apple's SFSpeechRecognizer
    private func transcribeWithAppleSpeech(audioURL: URL) async throws -> SpeechTranscriptionResult {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechServiceError.recognizerUnavailable
        }

        if !hasPermission {
            let granted = await requestPermission()
            guard granted else {
                throw SpeechServiceError.noPermission
            }
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard !hasResumed else { return }

                if let error {
                    hasResumed = true
                    continuation.resume(throwing: SpeechServiceError.transcriptionFailed(error))
                    return
                }

                guard let result, result.isFinal else { return }

                hasResumed = true
                let transcription = self?.processAppleTranscription(result) ?? SpeechTranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    words: [],
                    duration: 0
                )

                continuation.resume(returning: transcription)
            }
        }
    }

    private func processAppleTranscription(_ result: SFSpeechRecognitionResult) -> SpeechTranscriptionResult {
        let transcription = result.bestTranscription
        let segments = transcription.segments
        var words: [TranscriptionWord] = []
        var duration: TimeInterval = 0

        let pauseThreshold: TimeInterval = 0.3

        for (index, segment) in segments.enumerated() {
            let word = segment.substring
            let start = segment.timestamp
            let end = start + segment.duration
            let confidence = Double(segment.confidence)

            let previousWord = index > 0 ? segments[index - 1].substring : nil
            let nextWord = index < segments.count - 1 ? segments[index + 1].substring : nil

            let pauseBefore: Bool
            if index == 0 {
                pauseBefore = start > pauseThreshold
            } else {
                let previousEnd = segments[index - 1].timestamp + segments[index - 1].duration
                pauseBefore = (start - previousEnd) > pauseThreshold
            }

            let pauseAfter: Bool
            if index == segments.count - 1 {
                pauseAfter = true
            } else {
                let nextStart = segments[index + 1].timestamp
                pauseAfter = (nextStart - end) > pauseThreshold
            }

            let isStartOfSentence = index == 0 || (pauseBefore && (start - (segments[index - 1].timestamp + segments[index - 1].duration)) > 0.8)

            let isFiller = FillerWordList.isFillerWord(
                word,
                previousWord: previousWord,
                nextWord: nextWord,
                pauseBefore: pauseBefore,
                pauseAfter: pauseAfter,
                isStartOfSentence: isStartOfSentence
            )

            words.append(TranscriptionWord(
                word: word,
                start: start,
                end: end,
                confidence: confidence,
                isFiller: isFiller
            ))

            duration = max(duration, end)
        }

        words = detectFillerPhrases(in: words)

        return SpeechTranscriptionResult(
            text: transcription.formattedString,
            words: words,
            duration: duration
        )
    }

    private func detectFillerPhrases(in words: [TranscriptionWord]) -> [TranscriptionWord] {
        guard words.count >= 2 else { return words }

        var result = words

        for i in 0..<(result.count - 1) {
            if FillerWordList.isFillerPhrase(result[i].word, result[i + 1].word) {
                result[i] = TranscriptionWord(
                    word: result[i].word,
                    start: result[i].start,
                    end: result[i].end,
                    confidence: result[i].confidence,
                    isFiller: true
                )
                result[i + 1] = TranscriptionWord(
                    word: result[i + 1].word,
                    start: result[i + 1].start,
                    end: result[i + 1].end,
                    confidence: result[i + 1].confidence,
                    isFiller: true
                )
            }
        }

        return result
    }
    
    // MARK: - Analysis
    
    func analyze(transcription: SpeechTranscriptionResult, actualDuration: TimeInterval, vocabWords: [String] = []) -> SpeechAnalysis {
        // Count filler words
        var fillerCounts: [String: (count: Int, timestamps: [TimeInterval])] = [:]
        var totalWords = 0
        var pauses: [TimeInterval] = []
        
        var previousEnd: TimeInterval = 0
        
        for word in transcription.words {
            totalWords += 1
            
            // Check for filler words
            let lowercased = word.word.lowercased()
            if word.isFiller {
                var current = fillerCounts[lowercased] ?? (count: 0, timestamps: [])
                current.count += 1
                current.timestamps.append(word.start)
                fillerCounts[lowercased] = current
            }
            
            // Detect pauses (gap > 0.5 seconds)
            if previousEnd > 0 {
                let gap = word.start - previousEnd
                if gap > 0.5 {
                    pauses.append(gap)
                }
            }
            previousEnd = word.end
        }
        
        // Build filler words array
        let fillerWords = fillerCounts.map { key, value in
            FillerWord(word: key, count: value.count, timestamps: value.timestamps)
        }.sorted { $0.count > $1.count }
        
        // Calculate metrics
        let wordsPerMinute = actualDuration > 0 ? Double(totalWords) / (actualDuration / 60) : 0
        let totalFillers = fillerWords.reduce(0) { $0 + $1.count }
        let fillerRatio = totalWords > 0 ? Double(totalFillers) / Double(totalWords) : 0
        let averagePauseLength = pauses.isEmpty ? 0 : pauses.reduce(0, +) / Double(pauses.count)
        
        // Calculate scores
        let subscores = calculateSubscores(
            wordsPerMinute: wordsPerMinute,
            fillerRatio: fillerRatio,
            pauseCount: pauses.count,
            averagePauseLength: averagePauseLength,
            totalWords: totalWords
        )
        
        let overallScore = calculateOverallScore(subscores: subscores)
        let clarity = Double(100 - Int(fillerRatio * 100))
        
        // Detect vocab word usage
        let vocabWordsUsed = detectVocabWords(in: transcription.text, vocabWords: vocabWords)

        return SpeechAnalysis(
            fillerWords: fillerWords,
            totalWords: totalWords,
            wordsPerMinute: wordsPerMinute,
            pauseCount: pauses.count,
            averagePauseLength: averagePauseLength,
            clarity: clarity,
            speechScore: SpeechScore(
                overall: overallScore,
                subscores: subscores,
                trend: .stable // Will be calculated based on history
            ),
            vocabWordsUsed: vocabWordsUsed
        )
    }
    
    private func calculateSubscores(
        wordsPerMinute: Double,
        fillerRatio: Double,
        pauseCount: Int,
        averagePauseLength: TimeInterval,
        totalWords: Int
    ) -> SpeechSubscores {
        // Clarity score (based on confidence and articulation)
        // Higher is better, penalize high filler usage
        let clarityScore = max(0, min(100, Int(100 - (fillerRatio * 200))))
        
        // Pace score (optimal WPM is around 130-170)
        let paceScore: Int
        if wordsPerMinute < 100 {
            paceScore = max(0, Int(wordsPerMinute * 0.7)) // Too slow
        } else if wordsPerMinute > 200 {
            paceScore = max(0, 100 - Int((wordsPerMinute - 200) * 0.5)) // Too fast
        } else if wordsPerMinute >= 130 && wordsPerMinute <= 170 {
            paceScore = 100 // Optimal
        } else if wordsPerMinute < 130 {
            paceScore = 70 + Int((wordsPerMinute - 100) * 1.0) // Slightly slow
        } else {
            paceScore = 70 + Int((200 - wordsPerMinute) * 1.0) // Slightly fast
        }
        
        // Filler usage score (lower filler ratio = higher score)
        let fillerScore = max(0, min(100, Int((1 - fillerRatio * 5) * 100)))
        
        // Pause quality score
        // Good: Some pauses (0.5-2 seconds), not too many, not too few
        let pauseScore: Int
        let pausesPerMinute = totalWords > 0 ? Double(pauseCount) / Double(totalWords) * 60 : 0
        if pausesPerMinute < 2 {
            pauseScore = 60 // Too few pauses
        } else if pausesPerMinute > 10 {
            pauseScore = max(0, 100 - Int((pausesPerMinute - 10) * 5)) // Too many
        } else if averagePauseLength > 3 {
            pauseScore = max(0, 100 - Int((averagePauseLength - 3) * 20)) // Too long
        } else {
            pauseScore = min(100, 70 + Int(pausesPerMinute * 3))
        }
        
        return SpeechSubscores(
            clarity: clarityScore,
            pace: paceScore,
            fillerUsage: fillerScore,
            pauseQuality: pauseScore
        )
    }
    
    private func calculateOverallScore(subscores: SpeechSubscores) -> Int {
        // Weighted average
        let weights = (clarity: 0.3, pace: 0.25, filler: 0.3, pause: 0.15)
        
        let weighted = Double(subscores.clarity) * weights.clarity +
                       Double(subscores.pace) * weights.pace +
                       Double(subscores.fillerUsage) * weights.filler +
                       Double(subscores.pauseQuality) * weights.pause
        
        return max(0, min(100, Int(weighted)))
    }
    
    // MARK: - Vocab Word Detection

    private func detectVocabWords(in text: String, vocabWords: [String]) -> [VocabWordUsage] {
        guard !vocabWords.isEmpty, !text.isEmpty else { return [] }

        let lowercasedText = text.lowercased()
        var results: [VocabWordUsage] = []

        for vocabWord in vocabWords {
            let pattern = inflectedPattern(for: vocabWord)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let count = regex.numberOfMatches(in: lowercasedText, range: NSRange(lowercasedText.startIndex..., in: lowercasedText))
            if count > 0 {
                results.append(VocabWordUsage(word: vocabWord, count: count))
            }
        }

        return results.sorted { $0.count > $1.count }
    }

    /// Build a regex that matches a word and its common English inflections
    /// (plurals, past tense, progressive, comparative, adverb forms, etc.)
    private func inflectedPattern(for word: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        var alternatives: [String] = []

        // 1. Exact word + directly appended suffixes (e.g. "talk" → "talks", "talked", "talking")
        alternatives.append("\(escaped)(s|es|ed|d|ing|er|ers|est|ly)?")

        // 2. Words ending in 'e': drop 'e' before vowel-starting suffixes
        //    e.g. "create" → "creating", "created", "creative"
        if word.hasSuffix("e") {
            let stem = NSRegularExpression.escapedPattern(for: String(word.dropLast()))
            alternatives.append("\(stem)(ed|ing|er|ers|est|ive|ion|ation|y|ly)")
        }

        // 3. Words ending in consonant + 'y': change 'y' → 'i' before suffixes
        //    e.g. "happy" → "happier", "happiest", "happily", "happiness"
        if word.hasSuffix("y"), word.count > 1 {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let beforeY = word[word.index(word.endIndex, offsetBy: -2)]
            if !vowels.contains(beforeY) {
                let stem = NSRegularExpression.escapedPattern(for: String(word.dropLast()))
                alternatives.append("\(stem)i(es|ed|er|ier|est|iest|ly|ness)")
            }
        }

        // 4. CVC consonant doubling before vowel-starting suffixes
        //    e.g. "run" → "running", "runner"; "big" → "bigger", "biggest"
        let chars = Array(word.lowercased())
        if chars.count >= 3 {
            let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
            let last = chars[chars.count - 1]
            let secondLast = chars[chars.count - 2]
            let thirdLast = chars[chars.count - 3]
            let noDouble: Set<Character> = ["w", "x", "y"]
            if !vowels.contains(last) && vowels.contains(secondLast) && !vowels.contains(thirdLast) && !noDouble.contains(last) {
                let doubled = escaped + NSRegularExpression.escapedPattern(for: String(last))
                alternatives.append("\(doubled)(ing|ed|er|ers|est)")
            }
        }

        return "\\b(\(alternatives.joined(separator: "|")))\\b"
    }

    // MARK: - Vocab Word Marking on Transcript

    func markVocabWordsInTranscription(_ words: [TranscriptionWord], vocabWords: [String]) -> [TranscriptionWord] {
        guard !vocabWords.isEmpty else { return words }

        // Pre-compile regexes for each vocab word
        let regexes: [(String, NSRegularExpression)] = vocabWords.compactMap { vocab in
            let pattern = inflectedPattern(for: vocab)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return (vocab, regex)
        }

        return words.map { word in
            let cleaned = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            let matched = regexes.contains { _, regex in
                regex.firstMatch(in: cleaned, range: range) != nil
            }
            guard matched else { return word }
            return TranscriptionWord(
                word: word.word,
                start: word.start,
                end: word.end,
                confidence: word.confidence,
                isFiller: word.isFiller,
                isVocabWord: true
            )
        }
    }

    // MARK: - Trend Calculation
    
    func calculateTrend(currentScore: Int, historicalScores: [Int]) -> ScoreTrend {
        guard !historicalScores.isEmpty else { return .stable }
        
        let recentAverage = historicalScores.suffix(5).reduce(0, +) / max(1, historicalScores.suffix(5).count)
        let difference = currentScore - recentAverage
        
        if difference > 5 {
            return .improving
        } else if difference < -5 {
            return .declining
        }
        return .stable
    }
}

// MARK: - Result Types

struct SpeechTranscriptionResult {
    let text: String
    let words: [TranscriptionWord]
    let duration: TimeInterval
}

// MARK: - Errors

enum SpeechServiceError: LocalizedError {
    case noPermission
    case recognizerUnavailable
    case transcriptionFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Speech recognition permission is required to transcribe recordings."
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        }
    }
}

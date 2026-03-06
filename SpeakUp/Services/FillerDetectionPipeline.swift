import Foundation

// MARK: - Raw Word Timing

/// Common input format for filler detection, abstracted from WhisperKit/Apple Speech specifics.
struct RawWordTiming {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double

    init(word: String, start: TimeInterval, end: TimeInterval, confidence: Double = 1.0) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

// MARK: - Filler Detection Pipeline

/// Shared filler detection logic used by WhisperService, SpeechService, and LiveTranscriptionService.
/// Eliminates ~300 lines of duplicated pause/context computation + filler tagging + phrase detection.
enum FillerDetectionPipeline {

    // MARK: - Constants

    /// Gap (seconds) between words that counts as a pause for context-aware filler detection.
    static let pauseThreshold: TimeInterval = 0.3

    /// Gap (seconds) that indicates a sentence boundary.
    static let sentenceBoundaryThreshold: TimeInterval = 0.8

    // MARK: - Full Pipeline (returns TranscriptionWord array)

    /// Tag fillers in the given word timings.
    /// Computes pause/context for each word, runs `FillerWordList` context-aware detection,
    /// then detects multi-word filler phrases in a second pass.
    static func tagFillers(in words: [RawWordTiming]) -> [TranscriptionWord] {
        guard !words.isEmpty else { return [] }

        var result: [TranscriptionWord] = []

        for (index, timing) in words.enumerated() {
            let previousWord = index > 0 ? words[index - 1].word : nil
            let nextWord = index < words.count - 1 ? words[index + 1].word : nil

            let pauseBefore = computePauseBefore(index: index, words: words)
            let pauseAfter = computePauseAfter(index: index, words: words)
            let isStartOfSentence = computeIsStartOfSentence(index: index, words: words)

            let isFiller = FillerWordList.isFillerWord(
                timing.word,
                previousWord: previousWord,
                nextWord: nextWord,
                pauseBefore: pauseBefore,
                pauseAfter: pauseAfter,
                isStartOfSentence: isStartOfSentence
            )

            result.append(TranscriptionWord(
                word: timing.word,
                start: timing.start,
                end: timing.end,
                confidence: timing.confidence,
                isFiller: isFiller
            ))
        }

        // Second pass: detect multi-word filler phrases
        result = detectFillerPhrases(in: result)

        return result
    }

    // MARK: - Lightweight Count-Only (for LiveTranscriptionService)

    /// Count fillers without creating TranscriptionWord objects.
    /// Returns the set of indices that are fillers (single-word + phrase).
    static func countFillers(words: [String], timestamps: [TimeInterval], durations: [TimeInterval]) -> Int {
        guard words.count == timestamps.count, words.count == durations.count, !words.isEmpty else { return 0 }

        var fillerIndices = Set<Int>()

        for i in 0..<words.count {
            let word = words[i]
            let start = timestamps[i]
            let end = start + durations[i]
            let prev = i > 0 ? words[i - 1] : nil
            let next = i < words.count - 1 ? words[i + 1] : nil

            // Pause before
            let pauseBefore: Bool
            if i == 0 {
                pauseBefore = start > pauseThreshold
            } else {
                let prevEnd = timestamps[i - 1] + durations[i - 1]
                pauseBefore = (start - prevEnd) > pauseThreshold
            }

            // Pause after
            let pauseAfter: Bool
            if i == words.count - 1 {
                pauseAfter = true
            } else {
                let nextStart = timestamps[i + 1]
                pauseAfter = (nextStart - end) > pauseThreshold
            }

            // Sentence boundary
            let isStartOfSentence: Bool
            if i == 0 {
                isStartOfSentence = true
            } else {
                let prevEnd = timestamps[i - 1] + durations[i - 1]
                isStartOfSentence = (start - prevEnd) > sentenceBoundaryThreshold
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

        // Second pass: filler phrases
        if words.count >= 2 {
            for i in 0..<(words.count - 1) {
                if FillerWordList.isFillerPhrase(words[i], words[i + 1]) {
                    fillerIndices.insert(i)
                    fillerIndices.insert(i + 1)
                }
            }
        }

        return fillerIndices.count
    }

    // MARK: - Private Helpers

    private static func computePauseBefore(index: Int, words: [RawWordTiming]) -> Bool {
        if index == 0 {
            return words[index].start > pauseThreshold
        }
        return (words[index].start - words[index - 1].end) > pauseThreshold
    }

    private static func computePauseAfter(index: Int, words: [RawWordTiming]) -> Bool {
        if index == words.count - 1 {
            return true
        }
        return (words[index + 1].start - words[index].end) > pauseThreshold
    }

    private static func computeIsStartOfSentence(index: Int, words: [RawWordTiming]) -> Bool {
        if index == 0 {
            return true
        }
        return (words[index].start - words[index - 1].end) > sentenceBoundaryThreshold
    }

    private static func detectFillerPhrases(in words: [TranscriptionWord]) -> [TranscriptionWord] {
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
}

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
    var transcriptionEngine: String?

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
            transcriptionEngine = "WhisperKit"
            return result
        } catch {
            print("⚠️ WhisperKit failed: \(error). Retrying model load...")

            // Retry once: unload and reload the model
            whisperService.unloadModel()
            await whisperService.loadModel(modelVariant: "base")

            do {
                let result = try await whisperService.transcribe(audioURL: audioURL)
                transcriptionEngine = "WhisperKit (retry)"
                print("✅ WhisperKit retry succeeded")
                return result
            } catch {
                print("⚠️ WhisperKit retry failed: \(error). Falling back to Apple Speech (filler words may not be detected).")
                transcriptionEngine = "Apple Speech (fallback)"
                return try await transcribeWithAppleSpeech(audioURL: audioURL)
            }
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

        // Don't add punctuation — it makes Apple Speech more aggressive
        // about cleaning up raw speech and removing filler words
        request.addsPunctuation = false

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
        let segments = transcription.segments.sorted { $0.timestamp < $1.timestamp }
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

    func analyze(
        transcription: SpeechTranscriptionResult,
        actualDuration: TimeInterval,
        vocabWords: [String] = [],
        audioLevelSamples: [Float] = [],
        prompt: Prompt? = nil,
        targetWPM: Int = 150,
        trackFillerWords: Bool = true,
        trackPauses: Bool = true
    ) -> SpeechAnalysis {
        // Sort words by start time to ensure accurate pause detection
        // Whisper/Apple Speech results are usually sorted but segments can sometimes overlap or be out of order
        let sortedWords = transcription.words.sorted { $0.start < $1.start }
        
        // Count filler words
        var fillerCounts: [String: (count: Int, timestamps: [TimeInterval])] = [:]
        var totalWords = 0
        var pauseMetadata: [PauseInfo] = []

        var previousEnd: TimeInterval = 0

        for (index, word) in sortedWords.enumerated() {
            totalWords += 1

            // Check for filler words (honor settings flag)
            if trackFillerWords {
                let lowercased = word.word.lowercased()
                if word.isFiller {
                    var current = fillerCounts[lowercased] ?? (count: 0, timestamps: [])
                    current.count += 1
                    current.timestamps.append(word.start)
                    fillerCounts[lowercased] = current
                }
            }

            // Detect pauses (gap > 0.4 seconds) — honor settings flag
            if trackPauses, previousEnd > 0 {
                let gap = word.start - previousEnd
                if gap > 0.4 {
                    // Context detection
                    let isTransition: Bool
                    if index > 0 {
                        let prevWord = sortedWords[index - 1].word
                        isTransition = prevWord.hasSuffix(".") || prevWord.hasSuffix("?") || prevWord.hasSuffix("!")
                    } else {
                        isTransition = false
                    }
                    
                    pauseMetadata.append(PauseInfo(duration: gap, isTransition: isTransition, startTime: previousEnd))
                }
            }
            previousEnd = word.end
        }

        // Build filler words array
        let fillerWords = fillerCounts.map { key, value in
            FillerWord(word: key, count: value.count, timestamps: value.timestamps)
        }.sorted { $0.count > $1.count }

        let totalFillers = fillerWords.reduce(0) { $0 + $1.count }
        let wordsPerMinute = actualDuration > 0 ? Double(totalWords) / (actualDuration / 60) : 0

        // Confidence dampening for very short recordings (<10s)
        let confidenceWeight = min(1.0, actualDuration / 10.0)
        let fillerRatio = totalWords > 0 ? Double(totalFillers) / Double(totalWords) : 0
        let pauses = pauseMetadata.map { $0.duration }
        let averagePauseLength = pauses.isEmpty ? 0 : pauses.reduce(0, +) / Double(pauses.count)

        // Run sub-analyses that were previously orphaned
        let volumeMetrics = !audioLevelSamples.isEmpty ? analyzeVolume(samples: audioLevelSamples) : nil
        let vocabComplexity = !sortedWords.isEmpty ? analyzeVocabComplexity(words: sortedWords) : nil
        let sentenceAnalysis = !sortedWords.isEmpty ? analyzeSentenceStructure(words: sortedWords, text: transcription.text) : nil

        // Prompt relevance / coherence
        let relevanceScore: Int?
        if let prompt, totalWords >= 10 {
            relevanceScore = PromptRelevanceService.score(promptText: prompt.text, transcript: transcription.text)
        } else if totalWords >= 20 {
            relevanceScore = PromptRelevanceService.coherenceScore(transcript: transcription.text)
        } else {
            relevanceScore = nil
        }

        // Content density
        let contentDensity = contentDensityScore(words: sortedWords, totalFillers: totalFillers)

        // Detect vocab word usage (before subscores so we can feed it in)
        let vocabWordsUsed = detectVocabWords(in: transcription.text, vocabWords: vocabWords)

        // Count strategic vs hesitation pauses
        let strategicPauseCount = pauseMetadata.filter { $0.isTransition }.count
        let hesitationPauseCount = pauseMetadata.filter { !$0.isTransition && $0.duration > 1.2 }.count

        // Calculate subscores
        let subscores = calculateSubscores(
            wordsPerMinute: wordsPerMinute,
            fillerRatio: fillerRatio,
            pauseCount: pauses.count,
            averagePauseLength: averagePauseLength,
            totalWords: totalWords,
            confidenceWeight: confidenceWeight,
            targetWPM: targetWPM,
            trackPauses: trackPauses,
            actualDuration: actualDuration,
            words: sortedWords,
            volumeMetrics: volumeMetrics,
            vocabComplexity: vocabComplexity,
            sentenceAnalysis: sentenceAnalysis,
            relevanceScore: relevanceScore,
            contentDensity: contentDensity,
            vocabWordsUsed: vocabWordsUsed,
            pauseMetadata: pauseMetadata
        )

        var overallScore = calculateOverallScore(subscores: subscores)

        // Substance gate: very short recordings get capped
        if totalWords < 20 && actualDuration < 15 {
            overallScore = min(overallScore, 40)
        }

        let clarity = Double(subscores.clarity)

        return SpeechAnalysis(
            fillerWords: fillerWords,
            totalWords: totalWords,
            wordsPerMinute: wordsPerMinute,
            pauseCount: pauses.count,
            averagePauseLength: averagePauseLength,
            strategicPauseCount: strategicPauseCount,
            hesitationPauseCount: hesitationPauseCount,
            clarity: clarity,
            speechScore: SpeechScore(
                overall: overallScore,
                subscores: subscores,
                trend: .stable
            ),
            vocabWordsUsed: vocabWordsUsed,
            volumeMetrics: volumeMetrics,
            vocabComplexity: vocabComplexity,
            sentenceAnalysis: sentenceAnalysis,
            promptRelevanceScore: relevanceScore
        )
    }

    // MARK: - Content Density

    private func contentDensityScore(words: [TranscriptionWord], totalFillers: Int) -> Int {
        let nonFillerWords = words.filter { !$0.isFiller }
        guard !nonFillerWords.isEmpty else { return 0 }

        let cleaned = nonFillerWords.map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !Self.stopWords.contains($0) }

        guard !cleaned.isEmpty else { return 0 }

        let uniqueContent = Set(cleaned)
        let ratio = Double(uniqueContent.count) / Double(cleaned.count)
        return max(0, min(100, Int(ratio * 130))) // scale so ~77% unique content = 100
    }

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "it", "this", "that", "was", "are",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "can", "could", "should", "may", "might", "i", "you", "he", "she",
        "we", "they", "me", "my", "your", "his", "her", "our", "their",
        "not", "no", "if", "then", "than", "so", "as", "up", "out",
        "just", "also", "very", "too", "its", "all", "been", "being"
    ]

    // MARK: - Subscore Calculation

    private func calculateSubscores(
        wordsPerMinute: Double,
        fillerRatio: Double,
        pauseCount: Int,
        averagePauseLength: TimeInterval,
        totalWords: Int,
        confidenceWeight: Double = 1.0,
        targetWPM: Int = 150,
        trackPauses: Bool = true,
        actualDuration: TimeInterval = 60,
        words: [TranscriptionWord] = [],
        volumeMetrics: VolumeMetrics? = nil,
        vocabComplexity: VocabComplexity? = nil,
        sentenceAnalysis: SentenceAnalysis? = nil,
        relevanceScore: Int? = nil,
        contentDensity: Int = 50,
        vocabWordsUsed: [VocabWordUsage] = [],
        pauseMetadata: [PauseInfo] = []
    ) -> SpeechSubscores {
        // Clarity score — based on transcription confidence + word duration consistency
        let clarityScore: Int
        let confidences = words.compactMap { $0.confidence }
        if !confidences.isEmpty {
            let avgConfidence = confidences.reduce(0, +) / Double(confidences.count)
            let confidenceComponent = avgConfidence * 100 // 0-100

            // Word duration consistency: lower variance = steadier articulation
            let durations = words.map { $0.duration }.filter { $0 > 0 }
            let durationComponent: Double
            if durations.count >= 2 {
                let meanDur = durations.reduce(0, +) / Double(durations.count)
                let variance = durations.reduce(0.0) { $0 + pow($1 - meanDur, 2) } / Double(durations.count)
                let cv = meanDur > 0 ? sqrt(variance) / meanDur : 1.0 // coefficient of variation
                // CV of 0.3-0.5 is typical; lower = more consistent
                durationComponent = max(0, min(100, (1.0 - cv) * 100))
            } else {
                durationComponent = 50 // neutral when insufficient data
            }

            let rawClarity = confidenceComponent * 0.65 + durationComponent * 0.35
            clarityScore = max(0, min(100, Int(rawClarity * confidenceWeight + 50 * (1 - confidenceWeight))))
        } else {
            // Fallback when no confidence data: use inverse filler ratio
            let raw = 100 - (fillerRatio * 300)
            clarityScore = max(0, min(100, Int(raw * confidenceWeight + 50 * (1 - confidenceWeight))))
        }

        // Pace score: Gaussian centered on user's targetWPM
        let optimalWPM = Double(targetWPM)
        let sigma = 45.0
        let deviation = wordsPerMinute - optimalWPM
        let rawPaceScore = 100.0 * exp(-(deviation * deviation) / (2 * sigma * sigma))
        let paceScore = max(0, min(100, Int(rawPaceScore * confidenceWeight + 50 * (1 - confidenceWeight))))

        // Filler usage score — dampen for short recordings
        let rawFillerScore = (1 - fillerRatio * 5) * 100
        let fillerScore = max(0, min(100, Int(rawFillerScore * confidenceWeight + 50 * (1 - confidenceWeight))))

        // Pause quality score
        let pauseScore: Int
        if !trackPauses {
            pauseScore = 50 // Neutral when tracking is off
        } else {
            let rawPauseScore = calculatePauseScore(
                metadata: pauseMetadata,
                fillerRatio: fillerRatio,
                wordsPerMinute: wordsPerMinute,
                targetWPM: Double(targetWPM),
                actualDuration: actualDuration
            )
            pauseScore = max(0, min(100, Int(Double(rawPauseScore) * confidenceWeight + 50 * (1 - confidenceWeight))))
        }

        // Delivery score: volume energy + vocal variation + content density
        let deliveryScore: Int?
        if let vol = volumeMetrics {
            let energyComponent = Double(vol.energyScore) * 0.35
            let variationComponent = Double(vol.monotoneScore) * 0.35
            let densityComponent = Double(contentDensity) * 0.30
            deliveryScore = max(0, min(100, Int(energyComponent + variationComponent + densityComponent)))
        } else {
            deliveryScore = nil
        }

        // Vocabulary score — boost when user's word bank words are used
        var vocabularyScore = vocabComplexity?.complexityScore
        if let base = vocabularyScore, !vocabWordsUsed.isEmpty {
            let totalUsed = vocabWordsUsed.reduce(0) { $0 + $1.count }
            let bonus = min(15, totalUsed * 5) // up to +15 for 3+ vocab word uses
            vocabularyScore = min(100, base + bonus)
        }

        // Structure score
        let structureScore = sentenceAnalysis?.structureScore

        return SpeechSubscores(
            clarity: clarityScore,
            pace: paceScore,
            fillerUsage: fillerScore,
            pauseQuality: pauseScore,
            delivery: deliveryScore,
            vocabulary: vocabularyScore,
            structure: structureScore,
            relevance: relevanceScore
        )
    }

    /// Sophisticated pause scoring based on professional standards (e.g. Toastmasters)
    private func calculatePauseScore(
        metadata: [PauseInfo],
        fillerRatio: Double,
        wordsPerMinute: Double,
        targetWPM: Double,
        actualDuration: TimeInterval
    ) -> Int {
        guard !metadata.isEmpty else {
            // No pauses: if WPM is high, this is a major penalty (rushing)
            // If WPM is low/normal, it's just a moderate penalty
            return wordsPerMinute > (targetWPM + 20) ? 40 : 60
        }

        var score = 70.0 // Starting base score

        let shortPauses = metadata.filter { $0.duration >= 0.4 && $0.duration < 1.2 }
        let mediumPauses = metadata.filter { $0.duration >= 1.2 && $0.duration < 3.0 }
        let longPauses = metadata.filter { $0.duration >= 3.0 }

        // 1. Reward strategic Medium/Long pauses at transitions
        let strategicMediumCount = mediumPauses.filter { $0.isTransition }.count
        let strategicLongCount = longPauses.filter { $0.isTransition }.count
        score += Double(strategicMediumCount) * 4.0
        score += Double(strategicLongCount) * 8.0

        // 2. Penalize Long pauses NOT at transitions (hesitations)
        let hesitationLongCount = longPauses.filter { !$0.isTransition }.count
        score -= Double(hesitationLongCount) * 15.0

        // 3. Reward "Silence as Filler Replacement"
        // If filler ratio is low (< 0.02) and they have a healthy amount of short/medium pauses
        if fillerRatio < 0.02 && (shortPauses.count + mediumPauses.count) > 2 {
            score += 10.0
        }

        // 4. Frequency Check
        let pausesPerMinute = Double(metadata.count) / (actualDuration / 60)
        if pausesPerMinute < 3 {
            score -= 10.0 // Too few pauses = monolithic speech
        } else if pausesPerMinute > 15 {
            score -= (pausesPerMinute - 15) * 2.0 // Too many pauses = choppy
        }

        // 5. Pace Correlation
        // If they are rushing, they get a bigger bonus for strategic pauses
        if wordsPerMinute > (targetWPM + 10) {
            score += Double(strategicMediumCount + strategicLongCount) * 2.0
        }

        return max(0, min(100, Int(score)))
    }

    private func calculateOverallScore(subscores: SpeechSubscores) -> Int {
        // Weight distribution (totals 100% when all subscores present)
        var weighted = Double(subscores.clarity) * 0.15 +
                       Double(subscores.pace) * 0.18 +
                       Double(subscores.fillerUsage) * 0.15 +
                       Double(subscores.pauseQuality) * 0.13

        var totalWeight = 0.61

        if let delivery = subscores.delivery {
            weighted += Double(delivery) * 0.13
            totalWeight += 0.13
        }
        if let vocabulary = subscores.vocabulary {
            weighted += Double(vocabulary) * 0.09
            totalWeight += 0.09
        }
        if let structure = subscores.structure {
            weighted += Double(structure) * 0.05
            totalWeight += 0.05
        }
        if let relevance = subscores.relevance {
            weighted += Double(relevance) * 0.10
            totalWeight += 0.10
        }

        // Normalize by actual weight used (handles nil subscores)
        let normalized = weighted / totalWeight
        return max(0, min(100, Int(normalized)))
    }
    
    // MARK: - Volume Analysis

    func analyzeVolume(samples: [Float]) -> VolumeMetrics {
        guard !samples.isEmpty else { return VolumeMetrics() }

        let average = samples.reduce(0, +) / Float(samples.count)
        let peak = samples.max() ?? 0

        // Dynamic range: peak minus 5th percentile (ignoring outlier silence)
        let sorted = samples.sorted()
        let lowIdx = max(0, Int(Double(sorted.count) * 0.05))
        let highIdx = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        let dynamicRange = sorted[highIdx] - sorted[lowIdx]

        // Monotone score: based on standard deviation — higher variation = higher score
        let mean = Double(average)
        let variance = samples.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(samples.count)
        let stddev = sqrt(variance)
        // stddev of 5-15 dB is good variation for speech
        let monotoneScore = min(100, max(0, Int(stddev * 10)))

        // Energy score: based on average level relative to -40dB baseline
        // -40dB is quiet, 0dB is max; typical speech is -20 to -5 dB
        let normalizedAvg = max(0, min(1, (average + 40) / 40))
        let energyScore = min(100, max(0, Int(normalizedAvg * 100)))

        return VolumeMetrics(
            averageLevel: average,
            peakLevel: peak,
            dynamicRange: dynamicRange,
            monotoneScore: monotoneScore,
            energyScore: energyScore,
            levelSamples: samples
        )
    }

    // MARK: - Vocabulary Complexity Analysis

    func analyzeVocabComplexity(words: [TranscriptionWord]) -> VocabComplexity {
        guard !words.isEmpty else { return VocabComplexity() }

        let cleaned = words.map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let totalCount = cleaned.count
        guard totalCount > 0 else { return VocabComplexity() }

        let uniqueWords = Set(cleaned)
        let uniqueCount = uniqueWords.count
        let uniqueRatio = Double(uniqueCount) / Double(totalCount)

        let totalLength = cleaned.reduce(0) { $0 + $1.count }
        let avgLength = Double(totalLength) / Double(totalCount)

        let longWords = cleaned.filter { $0.count >= 7 }
        let longWordCount = longWords.count
        let longWordRatio = Double(longWordCount) / Double(totalCount)

        // Find repeated 2-3 word n-grams appearing 3+ times
        var phraseCounts: [String: Int] = [:]
        for n in 2...3 {
            guard cleaned.count >= n else { continue }
            for i in 0...(cleaned.count - n) {
                let phrase = cleaned[i..<(i + n)].joined(separator: " ")
                phraseCounts[phrase, default: 0] += 1
            }
        }
        let repeatedPhrases = phraseCounts
            .filter { $0.value >= 3 }
            .map { RepeatedPhrase(phrase: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        // Composite score: 40% unique ratio + 30% long word ratio + 30% inverse repeated phrases
        let uniqueComponent = min(1.0, uniqueRatio / 0.7) * 40 // 70% unique = full marks
        let longComponent = min(1.0, longWordRatio / 0.2) * 30 // 20% long words = full marks
        let repeatPenalty = min(1.0, Double(repeatedPhrases.count) / 5.0)
        let repeatComponent = (1.0 - repeatPenalty) * 30
        let score = min(100, max(0, Int(uniqueComponent + longComponent + repeatComponent)))

        return VocabComplexity(
            uniqueWordCount: uniqueCount,
            uniqueWordRatio: uniqueRatio,
            averageWordLength: avgLength,
            longWordCount: longWordCount,
            longWordRatio: longWordRatio,
            repeatedPhrases: Array(repeatedPhrases.prefix(10)),
            complexityScore: score
        )
    }

    // MARK: - Sentence Structure Analysis

    func analyzeSentenceStructure(words: [TranscriptionWord], text: String) -> SentenceAnalysis {
        guard !words.isEmpty else { return SentenceAnalysis() }

        // Split into sentences based on long pauses (>1.0s) or punctuation
        var sentences: [[TranscriptionWord]] = []
        var currentSentence: [TranscriptionWord] = []

        for (index, word) in words.enumerated() {
            currentSentence.append(word)

            let isEnd: Bool
            if word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!") {
                isEnd = true
            } else if index < words.count - 1 {
                let gap = words[index + 1].start - word.end
                isEnd = gap > 1.0
            } else {
                isEnd = true
            }

            if isEnd && !currentSentence.isEmpty {
                sentences.append(currentSentence)
                currentSentence = []
            }
        }
        if !currentSentence.isEmpty {
            sentences.append(currentSentence)
        }

        let totalSentences = sentences.count
        guard totalSentences > 0 else { return SentenceAnalysis() }

        let sentenceLengths = sentences.map { $0.count }
        let avgLength = Double(sentenceLengths.reduce(0, +)) / Double(totalSentences)
        let longestSentence = sentenceLengths.max() ?? 0

        // Detect incomplete sentences (<3 words)
        let incompleteSentences = sentences.filter { $0.count < 3 }.count

        // Detect restarts: "I think... I mean...", words repeated at sentence starts
        let restartPatterns = ["i mean", "what i'm saying", "let me", "i think i", "sorry"]
        var restartCount = 0
        var restartExamples: [String] = []

        for sentence in sentences {
            let sentenceText = sentence.map { $0.word.lowercased() }.joined(separator: " ")
            for pattern in restartPatterns {
                if sentenceText.contains(pattern) {
                    restartCount += 1
                    if restartExamples.count < 3 {
                        let example = sentence.prefix(6).map { $0.word }.joined(separator: " ")
                        restartExamples.append(example)
                    }
                    break
                }
            }
        }

        // Structure score
        let incompleteRatio = Double(incompleteSentences) / Double(totalSentences)
        let restartRatio = Double(restartCount) / Double(totalSentences)
        let runOnPenalty = sentences.filter { $0.count > 40 }.count

        var score = 100
        score -= Int(incompleteRatio * 30)
        score -= Int(restartRatio * 30)
        score -= runOnPenalty * 10
        if avgLength < 5 { score -= 10 }
        if avgLength > 30 { score -= 10 }
        score = max(0, min(100, score))

        return SentenceAnalysis(
            totalSentences: totalSentences,
            incompleteSentences: incompleteSentences,
            restartCount: restartCount,
            averageSentenceLength: avgLength,
            longestSentence: longestSentence,
            structureScore: score,
            restartExamples: restartExamples
        )
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

struct PauseInfo {
    let duration: TimeInterval
    let isTransition: Bool
    let startTime: TimeInterval
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

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
        audioURL: URL? = nil,
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

        // Run sub-analyses
        let volumeMetrics = !audioLevelSamples.isEmpty ? analyzeVolume(samples: audioLevelSamples) : nil
        let vocabComplexity = !sortedWords.isEmpty ? analyzeVocabComplexity(words: sortedWords) : nil
        let sentenceAnalysis = !sortedWords.isEmpty ? analyzeSentenceStructure(words: sortedWords, text: transcription.text) : nil

        // NEW: Pitch/prosody analysis from audio file
        let pitchMetrics: PitchMetrics?
        if let audioURL {
            pitchMetrics = PitchAnalysisService.analyze(audioURL: audioURL)
        } else {
            pitchMetrics = nil
        }

        // NEW: Speech rate variation analysis
        let rateVariation = analyzeRateVariation(words: sortedWords, actualDuration: actualDuration)

        // NEW: Emphasis detection
        let emphasisMetrics = analyzeEmphasis(words: sortedWords, actualDuration: actualDuration)

        // NEW: Energy arc analysis
        let energyArc = !audioLevelSamples.isEmpty ?
            analyzeEnergyArc(samples: audioLevelSamples, words: sortedWords, actualDuration: actualDuration) : nil

        // NEW: Text quality analysis (hedge words, power words, rhetorical devices)
        let textQuality = !transcription.text.isEmpty ?
            TextAnalysisService.analyze(text: transcription.text, totalWords: totalWords) : nil

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
            pauseMetadata: pauseMetadata,
            pitchMetrics: pitchMetrics,
            rateVariation: rateVariation,
            emphasisMetrics: emphasisMetrics,
            energyArc: energyArc,
            textQuality: textQuality
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
            promptRelevanceScore: relevanceScore,
            pitchMetrics: pitchMetrics,
            rateVariation: rateVariation,
            emphasisMetrics: emphasisMetrics,
            energyArc: energyArc,
            textQuality: textQuality
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
        pauseMetadata: [PauseInfo] = [],
        pitchMetrics: PitchMetrics? = nil,
        rateVariation: RateVariationMetrics? = nil,
        emphasisMetrics: EmphasisMetrics? = nil,
        energyArc: EnergyArcMetrics? = nil,
        textQuality: TextQualityMetrics? = nil
    ) -> SpeechSubscores {
        // Clarity score — based on transcription confidence + word duration consistency
        // Enhanced: hedge words reduce perceived clarity
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
                durationComponent = max(0, min(100, (1.0 - cv) * 100))
            } else {
                durationComponent = 50
            }

            // Hedge word penalty: high hedge ratio undermines clarity/authority
            let hedgePenalty: Double
            if let tq = textQuality {
                // hedgeWordRatio of 0.05 = 5% hedges → ~15pt penalty
                hedgePenalty = min(25, tq.hedgeWordRatio * 500)
            } else {
                hedgePenalty = 0
            }

            let rawClarity = confidenceComponent * 0.55 + durationComponent * 0.30 + (100 - hedgePenalty) * 0.15
            clarityScore = max(0, min(100, Int(rawClarity * confidenceWeight + 50 * (1 - confidenceWeight))))
        } else {
            let raw = 100 - (fillerRatio * 300)
            clarityScore = max(0, min(100, Int(raw * confidenceWeight + 50 * (1 - confidenceWeight))))
        }

        // Pace score: Gaussian centered on user's targetWPM
        // Enhanced: rate variation rewards dynamic pacing, penalizes monotone rate
        let optimalWPM = Double(targetWPM)
        let sigma = 45.0
        let deviation = wordsPerMinute - optimalWPM
        let basePaceScore = 100.0 * exp(-(deviation * deviation) / (2 * sigma * sigma))

        let rateVariationBonus: Double
        if let rv = rateVariation {
            // CV between 0.15-0.35 is ideal (purposeful variation without chaos)
            // variationScore is already 0-100
            rateVariationBonus = Double(rv.rateVariationScore) * 0.20 // up to +20 bonus
        } else {
            rateVariationBonus = 0
        }

        let rawPaceScore = basePaceScore * 0.80 + rateVariationBonus
        let paceScore = max(0, min(100, Int(rawPaceScore * confidenceWeight + 50 * (1 - confidenceWeight))))

        // Filler usage score — enhanced with hedge word awareness
        // Hedge words are "verbal fillers" that undermine authority ("kind of", "I think")
        let hedgeAdjustment: Double
        if let tq = textQuality {
            hedgeAdjustment = min(0.03, tq.hedgeWordRatio * 0.5) // counts as extra filler load
        } else {
            hedgeAdjustment = 0
        }
        let effectiveFillerRatio = fillerRatio + hedgeAdjustment
        let rawFillerScore = (1 - effectiveFillerRatio * 5) * 100
        let fillerScore = max(0, min(100, Int(rawFillerScore * confidenceWeight + 50 * (1 - confidenceWeight))))

        // Pause quality score
        let pauseScore: Int
        if !trackPauses {
            pauseScore = 50
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
        // Enhanced with emphasis and energy arc analysis
        let deliveryScore: Int?
        if let vol = volumeMetrics {
            let energyComponent = Double(vol.energyScore) * 0.25
            let variationComponent = Double(vol.monotoneScore) * 0.25
            let densityComponent = Double(contentDensity) * 0.15

            // Emphasis: speakers who emphasize key words score higher on delivery
            let emphasisComponent: Double
            if let em = emphasisMetrics {
                // emphasisPerMinute of 3-8 is ideal for engaged delivery
                let idealEmphasis = min(1.0, em.emphasisPerMinute / 5.0)
                emphasisComponent = idealEmphasis * 100.0 * 0.15
            } else {
                emphasisComponent = 50.0 * 0.15 // neutral
            }

            // Energy arc: strong opening and closing with sustained middle is ideal
            let arcComponent: Double
            if let arc = energyArc {
                arcComponent = Double(arc.arcScore) * 0.20
            } else {
                arcComponent = 50.0 * 0.20 // neutral
            }

            let rawDelivery = energyComponent + variationComponent + densityComponent + emphasisComponent + arcComponent
            deliveryScore = max(0, min(100, Int(rawDelivery)))
        } else {
            deliveryScore = nil
        }

        // Vocal Variety subscore (NEW) — combines pitch variation, volume dynamics, rate variation
        // This is a core differentiator: monotone speech is the #1 audience engagement killer
        let vocalVarietyScore: Int?
        if pitchMetrics != nil || volumeMetrics != nil || rateVariation != nil {
            var components: [Double] = []
            var weights: [Double] = []

            // Pitch variation: 45% weight — F0 range and variation are the strongest prosody signals
            if let pm = pitchMetrics {
                components.append(Double(pm.pitchVariationScore))
                weights.append(0.45)
            }

            // Volume dynamics: 25% weight — monotone volume = disengaged audience
            if let vol = volumeMetrics {
                components.append(Double(vol.monotoneScore))
                weights.append(0.25)
            }

            // Rate variation: 30% weight — varying pace keeps attention
            if let rv = rateVariation {
                components.append(Double(rv.rateVariationScore))
                weights.append(0.30)
            }

            if !components.isEmpty {
                let totalW = weights.reduce(0, +)
                let weightedSum = zip(components, weights).reduce(0.0) { $0 + $1.0 * $1.1 }
                let normalized = weightedSum / totalW
                vocalVarietyScore = max(0, min(100, Int(normalized * confidenceWeight + 50 * (1 - confidenceWeight))))
            } else {
                vocalVarietyScore = nil
            }
        } else {
            vocalVarietyScore = nil
        }

        // Vocabulary score — enhanced with power words and text quality metrics
        var vocabularyScore = vocabComplexity?.complexityScore
        if let base = vocabularyScore {
            // Boost for user's word bank usage
            if !vocabWordsUsed.isEmpty {
                let totalUsed = vocabWordsUsed.reduce(0) { $0 + $1.count }
                let vocabBonus = min(15, totalUsed * 5)
                vocabularyScore = min(100, base + vocabBonus)
            }
            // Boost for power words (action verbs, vivid language)
            if let tq = textQuality {
                // Scale power word count relative to total words for a ratio-like bonus
                let powerRatio = totalWords > 0 ? Double(tq.powerWordCount) / Double(totalWords) : 0
                let powerBonus = min(10, Int(powerRatio * 200)) // up to +10 for 5%+ power words
                vocabularyScore = min(100, (vocabularyScore ?? base) + powerBonus)
            }
        }

        // Structure score — enhanced with rhetorical devices and transition quality
        var structureScore = sentenceAnalysis?.structureScore
        if let base = structureScore, let tq = textQuality {
            // Rhetorical devices (tricolon, anaphora, contrast) demonstrate sophisticated structure
            let rhetoricBonus = min(12, tq.rhetoricalDeviceCount * 4)
            // Good transition variety demonstrates organized thought flow
            let transitionBonus = min(8, Int(Double(tq.transitionVariety) * 0.8))
            structureScore = min(100, base + rhetoricBonus + transitionBonus)
        }

        return SpeechSubscores(
            clarity: clarityScore,
            pace: paceScore,
            fillerUsage: fillerScore,
            pauseQuality: pauseScore,
            vocalVariety: vocalVarietyScore,
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
        // Revised weight distribution reflecting speech science research:
        // - Vocal Variety (16%): strongest predictor of audience engagement (Rosenberg & Hirschberg)
        // - Pace (14%): rate control is fundamental to comprehension
        // - Clarity (12%): articulation and confidence in delivery
        // - Filler (12%): filler word avoidance signals preparation and confidence
        // - Delivery (12%): energy, emphasis, and arc show intentional performance
        // - Pause (10%): strategic silence is a power tool
        // - Vocabulary (8%): word choice and complexity
        // - Structure (8%): organization and rhetorical devices
        // - Relevance (8%): staying on topic / coherence

        // Core subscores (always present)
        var weighted = Double(subscores.clarity) * 0.12 +
                       Double(subscores.pace) * 0.14 +
                       Double(subscores.fillerUsage) * 0.12 +
                       Double(subscores.pauseQuality) * 0.10

        var totalWeight = 0.48

        // Optional subscores — weight redistributes when absent
        if let vocalVariety = subscores.vocalVariety {
            weighted += Double(vocalVariety) * 0.16
            totalWeight += 0.16
        }
        if let delivery = subscores.delivery {
            weighted += Double(delivery) * 0.12
            totalWeight += 0.12
        }
        if let vocabulary = subscores.vocabulary {
            weighted += Double(vocabulary) * 0.08
            totalWeight += 0.08
        }
        if let structure = subscores.structure {
            weighted += Double(structure) * 0.08
            totalWeight += 0.08
        }
        if let relevance = subscores.relevance {
            weighted += Double(relevance) * 0.08
            totalWeight += 0.08
        }

        // Normalize by actual weight used (handles nil subscores gracefully)
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

    // MARK: - Rate Variation Analysis

    /// Analyze speech rate variation using rolling windows over word timestamps.
    /// Measures dynamic pacing — good speakers vary pace for emphasis and engagement.
    func analyzeRateVariation(words: [TranscriptionWord], actualDuration: TimeInterval) -> RateVariationMetrics {
        guard words.count >= 10, actualDuration > 5 else { return RateVariationMetrics() }

        let windowSize: TimeInterval = 10.0 // 10-second rolling windows
        let hopSize: TimeInterval = 5.0     // 5-second hop
        var windowedWPMs: [Double] = []

        var windowStart: TimeInterval = 0
        while windowStart + windowSize <= actualDuration {
            let windowEnd = windowStart + windowSize
            let wordsInWindow = words.filter { $0.start >= windowStart && $0.start < windowEnd && !$0.isFiller }
            let wpm = Double(wordsInWindow.count) / (windowSize / 60.0)
            if wpm > 0 {
                windowedWPMs.append(wpm)
            }
            windowStart += hopSize
        }

        guard windowedWPMs.count >= 2 else { return RateVariationMetrics() }

        let mean = windowedWPMs.reduce(0, +) / Double(windowedWPMs.count)
        let variance = windowedWPMs.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(windowedWPMs.count)
        let stddev = sqrt(variance)
        let cv = mean > 0 ? stddev / mean : 0
        let rateRange = (windowedWPMs.max() ?? 0) - (windowedWPMs.min() ?? 0)

        // Articulation rate: WPM excluding pauses (time spent actually speaking)
        let totalSpeechTime = words.reduce(0.0) { $0 + $1.duration }
        let articulationRate = totalSpeechTime > 0 ? Double(words.count) / (totalSpeechTime / 60.0) : 0

        // Rate variation score:
        // CV of 0.10-0.25 is healthy variation. Below 0.05 = monotone pace. Above 0.35 = erratic.
        let variationScore: Int
        if cv < 0.03 {
            variationScore = 20 // Nearly no variation — robotic
        } else if cv < 0.08 {
            variationScore = 40 + Int(cv * 400) // Some variation
        } else if cv <= 0.25 {
            variationScore = min(100, 60 + Int((cv - 0.08) * 235)) // Healthy dynamic range
        } else if cv <= 0.35 {
            variationScore = max(50, 100 - Int((cv - 0.25) * 300)) // Getting erratic
        } else {
            variationScore = max(20, 50 - Int((cv - 0.35) * 200)) // Too erratic
        }

        return RateVariationMetrics(
            rateCV: cv,
            articulationRate: articulationRate,
            rateRange: rateRange,
            windowedWPMs: windowedWPMs,
            rateVariationScore: variationScore
        )
    }

    // MARK: - Emphasis Detection

    /// Detect emphasized words where multiple prosodic cues align:
    /// longer duration + surrounding pauses + contextually prominent position.
    func analyzeEmphasis(words: [TranscriptionWord], actualDuration: TimeInterval) -> EmphasisMetrics {
        guard words.count >= 5, actualDuration > 0 else { return EmphasisMetrics() }

        let nonFillerWords = words.filter { !$0.isFiller }
        guard nonFillerWords.count >= 3 else { return EmphasisMetrics() }

        // Compute mean and stddev of word durations
        let durations = nonFillerWords.map { $0.duration }.filter { $0 > 0 }
        guard !durations.isEmpty else { return EmphasisMetrics() }
        let meanDur = durations.reduce(0, +) / Double(durations.count)
        let variance = durations.reduce(0.0) { $0 + pow($1 - meanDur, 2) } / Double(durations.count)
        let stdDur = sqrt(variance)
        let emphasisThreshold = meanDur + stdDur * 1.2 // Words 1.2 stddev above mean

        var emphasisPositions: [Double] = [] // Normalized position (0-1) in speech

        for (index, word) in words.enumerated() {
            guard !word.isFiller, word.duration > emphasisThreshold else { continue }

            // Check for surrounding pauses (at least one side)
            let pauseBefore: Bool
            if index > 0 {
                pauseBefore = (word.start - words[index - 1].end) > 0.2
            } else {
                pauseBefore = true
            }

            let pauseAfter: Bool
            if index < words.count - 1 {
                pauseAfter = (words[index + 1].start - word.end) > 0.2
            } else {
                pauseAfter = true
            }

            if pauseBefore || pauseAfter {
                let normalizedPos = word.start / actualDuration
                emphasisPositions.append(normalizedPos)
            }
        }

        let emphasisCount = emphasisPositions.count
        let emphasisPerMinute = actualDuration > 0 ? Double(emphasisCount) / (actualDuration / 60.0) : 0

        // Distribution score: well-distributed emphasis across the speech
        let distributionScore: Int
        if emphasisCount <= 1 {
            distributionScore = 30
        } else {
            // Divide speech into 4 quarters, check how many have at least one emphasis
            let quartiles = [0.0..<0.25, 0.25..<0.5, 0.5..<0.75, 0.75..<1.01]
            let quartersWithEmphasis = quartiles.filter { range in
                emphasisPositions.contains { range.contains($0) }
            }.count
            distributionScore = min(100, quartersWithEmphasis * 25)
        }

        return EmphasisMetrics(
            emphasisCount: emphasisCount,
            emphasisPerMinute: emphasisPerMinute,
            distributionScore: distributionScore
        )
    }

    // MARK: - Energy Arc Analysis

    /// Analyze the energy contour of a speech divided into thirds.
    /// Good speakers have dynamic energy structure (opening hooks, building climax, strong close).
    func analyzeEnergyArc(samples: [Float], words: [TranscriptionWord], actualDuration: TimeInterval) -> EnergyArcMetrics {
        guard !samples.isEmpty, actualDuration > 5 else { return EnergyArcMetrics() }

        let thirdSize = samples.count / 3
        guard thirdSize > 0 else { return EnergyArcMetrics() }

        func averageEnergy(_ slice: ArraySlice<Float>) -> Double {
            guard !slice.isEmpty else { return 0 }
            // Convert dB to linear, average, then normalize
            let linear = slice.map { pow(10, Double($0) / 20.0) }
            return linear.reduce(0, +) / Double(linear.count)
        }

        let opening = averageEnergy(samples[0..<thirdSize])
        let body = averageEnergy(samples[thirdSize..<(thirdSize * 2)])
        let closing = averageEnergy(samples[(thirdSize * 2)...])

        // Normalize to 0-1 range
        let maxEnergy = max(opening, body, closing, 0.001)
        let normOpening = opening / maxEnergy
        let normBody = body / maxEnergy
        let normClosing = closing / maxEnergy

        // Climax detection: is there a clear peak in any section?
        let hasClimax = max(normOpening, normBody, normClosing) > 0.85 &&
                         min(normOpening, normBody, normClosing) < 0.7

        // Arc score: rewards dynamic energy structure
        var arcScore = 50 // base

        // Reward strong openings (hook the audience)
        if normOpening > 0.7 { arcScore += 10 }

        // Reward strong closings (end with impact)
        if normClosing > 0.7 { arcScore += 15 }

        // Reward climax (energy builds somewhere)
        if hasClimax { arcScore += 10 }

        // Penalize completely flat energy
        let energyRange = max(normOpening, normBody, normClosing) - min(normOpening, normBody, normClosing)
        if energyRange < 0.1 {
            arcScore -= 15 // Monotone energy
        } else if energyRange > 0.2 {
            arcScore += 10 // Good dynamic range
        }

        // Penalize trailing off (closing much weaker than opening)
        if normClosing < normOpening * 0.5 {
            arcScore -= 10
        }

        arcScore = max(0, min(100, arcScore))

        return EnergyArcMetrics(
            openingEnergy: normOpening,
            bodyEnergy: normBody,
            closingEnergy: normClosing,
            hasClimax: hasClimax,
            arcScore: arcScore
        )
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

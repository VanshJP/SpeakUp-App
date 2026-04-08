import Foundation
import Speech
import AVFoundation
import NaturalLanguage

@Observable
class SpeechService {
    // State
    var isTranscribing = false
    var hasPermission = false
    var transcriptionProgress: Double = 0
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

    // MARK: - Lightweight Transcription (text only, no analysis)

    /// Fast transcription that skips isolation, speaker labeling, and filler detection.
    /// Use for dictation where you only need the raw text.
    func transcribeTextOnly(audioURL: URL, preferredTerms: [String] = []) async throws -> String {
        isTranscribing = true
        defer { isTranscribing = false }

        let result = try await whisperService.transcribe(audioURL: audioURL, preferredTerms: preferredTerms)
        return result.text
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        fillerConfig: FillerWordConfig = .default,
        preferredTerms: [String] = [],
        voiceProfile: VoiceProfile? = nil
    ) async throws -> SpeechTranscriptionResult {
        isTranscribing = true
        transcriptionProgress = 0

        defer {
            isTranscribing = false
            transcriptionProgress = 1.0
        }

        let isolationResult = SpeechIsolationService.preprocessIfBeneficial(audioURL: audioURL)
        let transcriptionURL = isolationResult?.processedAudioURL ?? audioURL
        let shouldCleanupProcessedFile = transcriptionURL != audioURL

        defer {
            if shouldCleanupProcessedFile {
                try? FileManager.default.removeItem(at: transcriptionURL)
            }
        }

        let result: SpeechTranscriptionResult

        do {
            // Use WhisperKit for accurate filler word detection
            result = try await whisperService.transcribe(audioURL: transcriptionURL, preferredTerms: preferredTerms)
            transcriptionProgress = whisperService.transcriptionProgress
        } catch {
            // Retry once: unload and reload the model
            whisperService.unloadModel()
            await whisperService.loadModel(modelVariant: "base")

            do {
                let retryResult = try await whisperService.transcribe(audioURL: transcriptionURL, preferredTerms: preferredTerms)
                result = retryResult
            } catch {
                result = try await transcribeWithAppleSpeech(audioURL: transcriptionURL)
            }
        }

        let wordsAfterFillerRetagging: [TranscriptionWord]
        if fillerConfig.customFillers.isEmpty && fillerConfig.removedDefaults.isEmpty {
            wordsAfterFillerRetagging = result.words
        } else {
            let rawTimings = result.words.map { w in
                RawWordTiming(word: w.word, start: w.start, end: w.end, confidence: w.confidence ?? 1.0)
            }
            wordsAfterFillerRetagging = FillerDetectionPipeline.tagFillers(in: rawTimings, config: fillerConfig)
        }

        var finalWords = wordsAfterFillerRetagging
        // Pre-load audio once for speaker isolation (avoids redundant file I/O)
        let preloaded = ConversationIsolationService.loadMonoPCM(url: transcriptionURL)
        let speakerLabeled = ConversationIsolationService.labelPrimarySpeaker(
            words: finalWords,
            audioURL: transcriptionURL,
            totalDuration: result.duration,
            persistentProfile: voiceProfile,
            preloadedSamples: preloaded.map { ($0.samples, $0.sampleRate) }
        )
        finalWords = speakerLabeled.0
        let speakerIsolationMetrics = speakerLabeled.1
        let voiceProfileUpdate = speakerLabeled.2
        let outputWords = isolatedPrimaryTranscriptWords(
            from: finalWords,
            metrics: speakerIsolationMetrics
        )
        let outputText = transcriptText(
            from: outputWords,
            fallback: result.text
        )

        return SpeechTranscriptionResult(
            text: outputText,
            words: outputWords,
            duration: result.duration,
            audioIsolationMetrics: isolationResult?.metrics,
            speakerIsolationMetrics: speakerIsolationMetrics,
            voiceProfileUpdate: voiceProfileUpdate
        )
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

        let rawTimings = segments.map { segment in
            RawWordTiming(
                word: segment.substring,
                start: segment.timestamp,
                end: segment.timestamp + segment.duration,
                confidence: Double(segment.confidence)
            )
        }

        let words = FillerDetectionPipeline.tagFillers(in: rawTimings)
        let duration = rawTimings.last?.end ?? 0

        return SpeechTranscriptionResult(
            text: transcription.formattedString,
            words: words,
            duration: duration
        )
    }
    
    // MARK: - Analysis

    func analyze(
        transcription: SpeechTranscriptionResult,
        actualDuration: TimeInterval,
        vocabWords: [String] = [],
        audioLevelSamples: [Float] = [],
        audioURL: URL? = nil,
        promptText: String? = nil,
        targetWPM: Int = 150,
        trackFillerWords: Bool = true,
        trackPauses: Bool = true,
        scoreWeights: ScoreWeights = .defaults,
        audioIsolationMetrics: AudioIsolationMetrics? = nil,
        speakerIsolationMetrics: SpeakerIsolationMetrics? = nil
    ) -> SpeechAnalysis {
        // Sort words by start time to ensure accurate pause detection
        // Whisper/Apple Speech results are usually sorted but segments can sometimes overlap or be out of order
        let sortedWords = transcription.words.sorted { $0.start < $1.start }

        let primarySpeakerWords = sortedWords.filter(\.isPrimarySpeaker)
        let shouldUsePrimarySpeakerWords = shouldScoreUsingPrimarySpeakerWords(
            totalWords: sortedWords.count,
            primaryWordsCount: primarySpeakerWords.count,
            speakerIsolationMetrics: speakerIsolationMetrics
        )
        let scoringWords = shouldUsePrimarySpeakerWords ? primarySpeakerWords : sortedWords
        let scoringText = scoringWords.map(\.word).joined(separator: " ")

        // Count filler words
        var fillerCounts: [String: (count: Int, timestamps: [TimeInterval])] = [:]
        var totalWords = 0
        var pauseMetadata: [PauseInfo] = []

        var previousEnd: TimeInterval = 0

        for (index, word) in scoringWords.enumerated() {
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
                    let cappedDuration = min(gap, 10.0)  // Cap at 10s — longer gaps are recording artifacts
                    // Context detection
                    let isTransition: Bool
                    if index > 0 {
                        let prevWord = scoringWords[index - 1].word
                        isTransition = prevWord.hasSuffix(".") || prevWord.hasSuffix("?") || prevWord.hasSuffix("!")
                    } else {
                        isTransition = false
                    }

                    pauseMetadata.append(PauseInfo(duration: cappedDuration, isTransition: isTransition, startTime: previousEnd))
                }
            }
            previousEnd = word.end
        }

        // Build filler words array
        let fillerWords = fillerCounts.map { key, value in
            FillerWord(word: key, count: value.count, timestamps: value.timestamps)
        }.sorted { $0.count > $1.count }

        let totalFillers = fillerWords.reduce(0) { $0 + $1.count }
        let scoringDuration = effectiveSpeechDuration(words: scoringWords, fallback: actualDuration)
        let wordsPerMinute = scoringDuration > 0 ? Double(totalWords) / (scoringDuration / 60) : 0

        let pauses = pauseMetadata.map { $0.duration }
        // Use median to resist outlier skew from long recording gaps
        let averagePauseLength: Double
        if pauses.isEmpty {
            averagePauseLength = 0
        } else {
            let sortedPauses = pauses.sorted()
            let mid = sortedPauses.count / 2
            if sortedPauses.count % 2 == 0 {
                averagePauseLength = (sortedPauses[mid - 1] + sortedPauses[mid]) / 2.0
            } else {
                averagePauseLength = sortedPauses[mid]
            }
        }

        // Count strategic vs hesitation pauses
        let strategicPauseCount = pauseMetadata.filter { $0.isTransition }.count
        let hesitationPauseCount = pauseMetadata.filter { !$0.isTransition && $0.duration > 1.2 }.count

        // Run sub-analyses
        let volumeMetrics = !audioLevelSamples.isEmpty ? analyzeVolume(samples: audioLevelSamples) : nil
        let vocabComplexity = !scoringWords.isEmpty ? analyzeVocabComplexity(words: scoringWords) : nil
        let sentenceAnalysis = !scoringWords.isEmpty ? analyzeSentenceStructure(words: scoringWords) : nil

        // Advanced analyses
        let pitchMetrics: PitchMetrics? = audioURL != nil ? PitchAnalysisService.analyze(audioURL: audioURL!) : nil
        let rateVariation = analyzeRateVariation(words: scoringWords, actualDuration: scoringDuration)
        let emphasisMetrics = analyzeEmphasis(
            words: scoringWords,
            actualDuration: scoringDuration,
            pitchContour: pitchMetrics?.f0Contour,
            audioLevelSamples: audioLevelSamples
        )
        let energyArc = !audioLevelSamples.isEmpty ?
            analyzeEnergyArc(samples: audioLevelSamples, words: scoringWords, actualDuration: scoringDuration) : nil
        let textQuality = !scoringText.isEmpty ?
            TextAnalysisService.analyze(text: scoringText, totalWords: totalWords) : nil

        // Zero-score gate: no meaningful speech
        let nonFillerWordCount = totalWords - totalFillers
        if totalWords == 0 || nonFillerWordCount == 0 {
            return SpeechAnalysis(
                fillerWords: fillerWords,
                totalWords: totalWords,
                wordsPerMinute: 0,
                pauseCount: pauses.count,
                averagePauseLength: averagePauseLength,
                strategicPauseCount: strategicPauseCount,
                hesitationPauseCount: hesitationPauseCount,
                clarity: 0,
                speechScore: SpeechScore(overall: 0, subscores: SpeechSubscores(), trend: .stable),
                vocabWordsUsed: [],
                volumeMetrics: volumeMetrics,
                sentenceAnalysis: sentenceAnalysis,
                promptRelevanceScore: nil,
                audioIsolationMetrics: audioIsolationMetrics,
                speakerIsolationMetrics: speakerIsolationMetrics
            )
        }

        let fillerRatio = totalWords > 0 ? Double(totalFillers) / Double(totalWords) : 0

        // Prompt relevance / coherence
        let relevanceScore: Int?
        if let promptText, totalWords >= 10 {
            relevanceScore = PromptRelevanceService.score(promptText: promptText, transcript: scoringText)
        } else if totalWords >= 20 {
            relevanceScore = PromptRelevanceService.coherenceScore(transcript: scoringText)
        } else {
            relevanceScore = nil
        }

        // Content density
        let contentDensity = contentDensityScore(words: scoringWords)

        // Detect vocab word usage (before subscores so we can feed it in)
        let vocabWordsUsed = detectVocabWords(in: scoringText, vocabWords: vocabWords)

        // ── Enhanced Scoring Engine ──────────────────────────────────────────────────
        // Compute research-backed metrics: MATTR, PTR, MLR, substance, fluency, gibberish.
        let enhancedMetrics = SpeechScoringEngine.computeEnhancedMetrics(
            words: scoringWords,
            scoringText: scoringText,
            actualDuration: actualDuration,
            pauseMetadata: pauseMetadata
        )

        // Calculate subscores
        let subscores = calculateSubscores(
            wordsPerMinute: wordsPerMinute,
            fillerRatio: fillerRatio,
            totalWords: totalWords,
            targetWPM: targetWPM,
            trackPauses: trackPauses,
            actualDuration: actualDuration,
            words: scoringWords,
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
            textQuality: textQuality,
            audioLevelSamples: audioLevelSamples,
            audioIsolationMetrics: audioIsolationMetrics,
            speakerIsolationMetrics: speakerIsolationMetrics,
            enhancedMetrics: enhancedMetrics
        )

        var overallScore = calculateOverallScore(subscores: subscores, weights: scoreWeights)

        // ── Substance Gate (replaces simple word-count cap) ──────────────────────────
        // Apply substance score as a MULTIPLIER, not just a ceiling.
        // This ensures gibberish/near-empty speech collapses to near-zero regardless
        // of how "fluent" the few words were.
        overallScore = SpeechScoringEngine.applySubstanceMultiplier(
            overallScore: overallScore,
            substanceScore: enhancedMetrics.substanceScore
        )

        // ── Enhanced Gibberish Gate ──────────────────────────────────────────────────
        // Multi-signal gibberish detection replaces the old binary isLikelyGibberish check.
        // Uses confidence score for graduated capping rather than a hard binary.
        overallScore = SpeechScoringEngine.applyGibberishGate(
            score: overallScore,
            gibberishConfidence: enhancedMetrics.gibberishConfidence
        )

        // NOTE: The legacy binary isLikelyGibberish gate has been removed.
        // SpeechScoringEngine.applyGibberishGate uses a graduated 5-signal confidence
        // score (0.0-1.0) which is strictly more accurate and less prone to false positives.
        // PromptRelevanceService.isLikelyGibberish is retained as a standalone utility
        // for other callers (e.g., UI pre-flight checks) but no longer gates scoring.

        let clarity = Double(subscores.clarity)

        // Compute WPM time series
        let wpmTimeSeries = computeWPMTimeSeries(words: scoringWords, actualDuration: scoringDuration)

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
            wpmTimeSeries: wpmTimeSeries,
            pitchMetrics: pitchMetrics,
            rateVariation: rateVariation,
            emphasisMetrics: emphasisMetrics,
            energyArc: energyArc,
            textQuality: textQuality,
            audioIsolationMetrics: audioIsolationMetrics,
            speakerIsolationMetrics: speakerIsolationMetrics,
            enhancedMetrics: enhancedMetrics
        )
    }

    // MARK: - Content Density

    private func contentDensityScore(words: [TranscriptionWord]) -> Int {
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

    private func effectiveSpeechDuration(words: [TranscriptionWord], fallback: TimeInterval) -> TimeInterval {
        guard let first = words.first, let last = words.last else { return fallback }
        let activeWindow = max(0, last.end - first.start)
        return max(activeWindow, min(fallback, 5.0))
    }

    private func applyReliabilityStabilization(score: Int, reliability: Double, neutralAnchor: Int) -> Int {
        // Only apply stabilization when reliability is genuinely degraded.
        // The original code clamped reliability to max(0.55, ...) which meant even
        // perfect solo sessions (reliability = 1.0) got a 0% pull toward the neutral
        // anchor — which is correct. However, the clamp also meant the minimum blend
        // was 55% score + 45% anchor, which is too aggressive for moderately-reliable
        // sessions. The new formula:
        //   - reliability >= 0.95: no stabilization at all (pass score through unchanged)
        //   - reliability in [0.55, 0.95): linear blend from 0% to 45% anchor pull
        //   - reliability < 0.55: clamp at 55% score / 45% anchor (same as before)
        // This means solo recordings are never penalized, and only genuinely noisy or
        // ambiguous multi-speaker sessions get their scores pulled toward neutral.
        guard reliability < 0.95 else { return max(0, min(100, score)) }
        let clampedReliability = max(0.55, min(0.95, reliability))
        let blended = Double(score) * clampedReliability + Double(neutralAnchor) * (1.0 - clampedReliability)
        return max(0, min(100, Int(blended.rounded())))
    }

    private func combinedReliabilityScore(
        audioIsolationMetrics: AudioIsolationMetrics?,
        speakerIsolationMetrics: SpeakerIsolationMetrics?
    ) -> Double {
        let signalReliability = audioIsolationMetrics.map { metrics in
            let residual = max(0.0, min(1.0, Double(metrics.residualNoiseScore) / 100.0))
            // Keep sessions near full reliability unless residual noise is clearly poor.
            if residual >= 0.55 { return 1.0 }
            return max(0.55, residual * 0.70 + 0.30)
        }
        let speakerReliability: Double? = speakerIsolationMetrics.flatMap { metrics -> Double? in
            // Only apply speaker reliability dampening when isolation was actually applied
            // AND there is meaningful evidence of a multi-speaker conversation.
            // Previously, any session with filteredOutWordCount >= 4 would trigger dampening,
            // even if those 4 words were just noise artifacts in a solo recording.
            // Now we require conversationDetected OR (filteredOut >= 4 AND switchCount >= 3)
            // to avoid penalizing clean solo sessions with minor noise.
            let hasAppliedSeparationEvidence =
                metrics.conversationDetected ||
                (metrics.filteredOutWordCount >= 4 && metrics.speakerSwitchCount >= 3)
            guard hasAppliedSeparationEvidence else { return nil }

            let confidence = max(0.0, min(1.0, Double(metrics.separationConfidence) / 100.0))
            // Raised the pass-through threshold from 0.65 to 0.70:
            // At 70%+ confidence the isolation is reliable enough to not dampen scores.
            if confidence >= 0.70 { return 1.0 }
            return max(0.55, confidence * 0.70 + 0.30)
        }

        switch (signalReliability, speakerReliability) {
        case let (.some(signal), .some(speaker)):
            return max(0.35, min(1.0, signal * 0.6 + speaker * 0.4))
        case let (.some(signal), .none):
            return max(0.35, min(1.0, signal))
        case let (.none, .some(speaker)):
            return max(0.35, min(1.0, speaker))
        case (.none, .none):
            // Do not dampen scores when no reliability signals were produced.
            return 1.0
        }
    }

    private func shouldScoreUsingPrimarySpeakerWords(
        totalWords: Int,
        primaryWordsCount: Int,
        speakerIsolationMetrics: SpeakerIsolationMetrics?
    ) -> Bool {
        guard totalWords >= 12, let metrics = speakerIsolationMetrics else { return false }

        // Raised minimum primary words from 45% to 55% of total.
        // Scoring on fewer than 55% of words means we're discarding nearly half the speech,
        // which produces an unreliable score. Better to fall back to full transcript.
        let minimumPrimaryWords = max(10, Int(Double(totalWords) * 0.55))
        guard primaryWordsCount >= minimumPrimaryWords else { return false }

        // Raised confidence threshold from 58 to 62.
        // The ConversationIsolationService confidence formula now starts at 28 (was 35),
        // so the effective bar is higher. 62 corresponds to clear acoustic separation.
        guard metrics.separationConfidence >= 62 else { return false }

        // Tightened ratio range: lower bound raised from 0.45 to 0.55 (matching minimumPrimaryWords),
        // upper bound lowered from 0.92 to 0.90 (if 90%+ are primary, it's likely a solo session
        // and we should score on all words rather than filtering out the few non-primary ones).
        guard (0.55...0.90).contains(metrics.primarySpeakerWordRatio) else { return false }

        // Require slightly more evidence: filteredOut must be at least 18% of total (was 15%).
        // This ensures we only apply isolation when there's a meaningful amount of other-speaker speech.
        let minimumFilteredOutWords = max(4, Int(Double(totalWords) * 0.18))
        let hasConversationEvidence =
            metrics.conversationDetected ||
            (metrics.filteredOutWordCount >= minimumFilteredOutWords && metrics.speakerSwitchCount >= 2)

        return hasConversationEvidence
    }

    private func isolatedPrimaryTranscriptWords(
        from words: [TranscriptionWord],
        metrics: SpeakerIsolationMetrics?
    ) -> [TranscriptionWord] {
        let primaryWords = words.filter(\.isPrimarySpeaker)
        let shouldFilter = shouldScoreUsingPrimarySpeakerWords(
            totalWords: words.count,
            primaryWordsCount: primaryWords.count,
            speakerIsolationMetrics: metrics
        )
        return shouldFilter ? primaryWords : words
    }

    private func transcriptText(from words: [TranscriptionWord], fallback: String) -> String {
        let resolved = words
            .map(\.word)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? fallback : resolved
    }

    // MARK: - Subscore Calculation

    private func calculateSubscores(
        wordsPerMinute: Double,
        fillerRatio: Double,
        totalWords: Int,
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
        textQuality: TextQualityMetrics? = nil,
        audioLevelSamples: [Float] = [],
        audioIsolationMetrics: AudioIsolationMetrics? = nil,
        speakerIsolationMetrics: SpeakerIsolationMetrics? = nil,
        enhancedMetrics: EnhancedSpeechMetrics? = nil
    ) -> SpeechSubscores {
        // NOTE: The old per-subscore scoreCeiling (40 + duration*6) has been removed.
        // Short-speech penalty is now handled holistically by SpeechScoringEngine.applySubstanceMultiplier
        // which applies a graduated multiplier to the final overall score. This prevents the
        // ceiling from artificially compressing subscores while still penalizing short/empty speech.

        // Clarity score — voiced frame ratio + duration consistency + hedge penalty + authority.
        // Tuned so average conversational speech lands in the 60-75 range, not the 40-55 range.
        let clarityScore: Int
        do {
            let articulationComponent: Double
            if let pm = pitchMetrics, pm.voicedFrameRatio > 0 {
                articulationComponent = min(100, max(0, Double(pm.voicedFrameRatio) * 110 + 38))
            } else {
                let confidences = words.compactMap { $0.confidence }
                if !confidences.isEmpty {
                    let averageConfidence = confidences.reduce(0, +) / Double(confidences.count)
                    articulationComponent = min(100, max(40, averageConfidence * 100 + 20))
                } else {
                    articulationComponent = 65
                }
            }

            let durations = words.map { $0.duration }.filter { $0 > 0 }
            let durationComponent: Double
            if durations.count >= 2 {
                let meanDur = durations.reduce(0, +) / Double(durations.count)
                let variance = durations.reduce(0.0) { $0 + pow($1 - meanDur, 2) } / Double(durations.count)
                let cv = meanDur > 0 ? sqrt(variance) / meanDur : 1.0
                durationComponent = max(0, min(100, (1.0 - cv * 0.50) * 100))
            } else {
                durationComponent = 60
            }

            let hedgePenalty: Double
            if let tq = textQuality {
                hedgePenalty = min(10, tq.hedgeWordRatio * 200)
            } else {
                hedgePenalty = 0
            }

            let authorityComponent: Double
            if let tq = textQuality {
                authorityComponent = Double(tq.authorityScore)
            } else {
                authorityComponent = 60
            }

            let paceAlignmentBonus = max(0, 8 - abs(wordsPerMinute - Double(targetWPM)) / 12)
            let rawClarity = articulationComponent * 0.50 +
                durationComponent * 0.22 +
                (100 - hedgePenalty) * 0.08 +
                authorityComponent * 0.12 +
                paceAlignmentBonus
            clarityScore = max(0, min(100, Int(rawClarity)))
        }

        // Pace score — WPM Gaussian + optional rate variation and fluency bonuses.
        // Sigma widened from 45→55 so WPM ±30 from target still scores well.
        // When optional metrics are available they replace part of the base weight;
        // when absent, WPM gets the full weight so the score isn't artificially capped.
        let optimalWPM = Double(targetWPM)
        let sigma = 55.0
        let deviation = wordsPerMinute - optimalWPM
        let basePaceScore = 100.0 * exp(-(deviation * deviation) / (2 * sigma * sigma))

        var paceBaseWeight = 1.0
        var bonusComponents = 0.0

        if let rv = rateVariation {
            bonusComponents += Double(rv.rateVariationScore) * 0.18
            paceBaseWeight -= 0.18
        }
        if let em = enhancedMetrics {
            bonusComponents += Double(em.fluencyScore) * 0.14
            paceBaseWeight -= 0.14
        }

        let rawPaceScore = basePaceScore * paceBaseWeight + bonusComponents
        let paceScore = max(0, min(100, Int(rawPaceScore)))

        // Filler usage score — gentler log curve so beginners can see progress.
        // Old multiplier of 20 was brutal: 5% fillers → score 0. New multiplier of 8
        // means 5% fillers → ~52, 3% → ~72, 1% → ~91, giving room to improve.
        let hedgeAdjustment: Double
        let weakPhraseAdjustment: Double
        if let tq = textQuality {
            hedgeAdjustment = min(0.02, tq.hedgeWordRatio * 0.35)
            weakPhraseAdjustment = min(0.02, tq.weakPhraseRatio * 0.5)
        } else {
            hedgeAdjustment = 0
            weakPhraseAdjustment = 0
        }
        let effectiveFillerRatio = fillerRatio + hedgeAdjustment + weakPhraseAdjustment
        let rawFillerScore = 100.0 * max(0, 1.0 - log2(1.0 + effectiveFillerRatio * 8.0))
        let fillerScore = max(0, min(100, Int(rawFillerScore)))

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
            pauseScore = max(0, min(100, rawPauseScore))
        }

        let combinedReliability = combinedReliabilityScore(
            audioIsolationMetrics: audioIsolationMetrics,
            speakerIsolationMetrics: speakerIsolationMetrics
        )
        let neutralAnchor = 55

        let stabilizedClarity = applyReliabilityStabilization(
            score: clarityScore,
            reliability: combinedReliability,
            neutralAnchor: neutralAnchor
        )
        let stabilizedPace = applyReliabilityStabilization(
            score: paceScore,
            reliability: combinedReliability,
            neutralAnchor: neutralAnchor
        )
        let stabilizedFiller = applyReliabilityStabilization(
            score: fillerScore,
            reliability: combinedReliability,
            neutralAnchor: neutralAnchor
        )
        let stabilizedPause = applyReliabilityStabilization(
            score: pauseScore,
            reliability: combinedReliability,
            neutralAnchor: neutralAnchor
        )

        // Delivery score — enhanced with emphasis and energy arc
        let deliveryScore: Int?
        if let vol = volumeMetrics {
            let energyComponent = Double(vol.energyScore) * 0.25
            let variationComponent = Double(vol.monotoneScore) * 0.25
            let densityComponent = Double(contentDensity) * 0.10

            let emphasisComponent: Double
            if let em = emphasisMetrics {
                let idealEmphasis = min(1.0, em.emphasisPerMinute / 5.0)
                emphasisComponent = idealEmphasis * 100.0 * 0.15
            } else {
                emphasisComponent = 50.0 * 0.15
            }

            let arcComponent: Double
            if let arc = energyArc {
                arcComponent = Double(arc.arcScore) * 0.20
            } else {
                arcComponent = 50.0 * 0.20
            }

            let engagementComponent: Double
            if let tq = textQuality {
                engagementComponent = Double(tq.engagementScore) * 0.05
            } else {
                engagementComponent = 50.0 * 0.05
            }

            let rawDelivery = energyComponent +
                variationComponent +
                densityComponent +
                emphasisComponent +
                arcComponent +
                engagementComponent
            deliveryScore = max(0, min(100, Int(rawDelivery)))
        } else {
            deliveryScore = nil
        }

        // Vocal Variety subscore — pitch + volume dynamics + rate variation + cross-signal correlation
        let vocalVarietyScore: Int?
        if pitchMetrics != nil || volumeMetrics != nil || rateVariation != nil {
            var components: [Double] = []
            var weights: [Double] = []

            if let pm = pitchMetrics {
                components.append(Double(pm.pitchVariationScore))
                weights.append(0.40)  // Pitch is primary signal for vocal variety
            }
            if let vol = volumeMetrics {
                components.append(Double(vol.monotoneScore))
                weights.append(0.25)
            }
            if let rv = rateVariation {
                components.append(Double(rv.rateVariationScore))
                weights.append(0.15)  // Reduced: pace variation is weakly correlated with vocal variety
            }

            // Cross-signal correlation: engaging speakers modulate pitch and energy together
            if let pm = pitchMetrics, let contour = pm.f0Contour, !audioLevelSamples.isEmpty {
                let correlationScore = PitchAnalysisService.pitchEnergyCorrelation(
                    pitchContour: contour,
                    audioLevelSamples: audioLevelSamples
                )
                components.append(Double(correlationScore))
                weights.append(0.20)
            }

            if !components.isEmpty {
                let totalW = weights.reduce(0, +)
                let weightedSum = zip(components, weights).reduce(0.0) { $0 + $1.0 * $1.1 }
                let normalized = weightedSum / totalW
                vocalVarietyScore = max(0, min(100, Int(normalized)))
            } else {
                vocalVarietyScore = nil
            }
        } else {
            vocalVarietyScore = nil
        }

        // Vocabulary score — enhanced with MATTR lexical diversity and word rarity
        var vocabularyScore = vocabComplexity?.complexityScore
        if let base = vocabularyScore {
            if !vocabWordsUsed.isEmpty {
                let totalUsed = vocabWordsUsed.reduce(0) { $0 + $1.count }
                let vocabBonus = min(8, totalUsed * 3)  // Capped at +8 (down from +15)
                vocabularyScore = min(100, base + vocabBonus)
            }
            if let tq = textQuality {
                let powerRatio = totalWords > 0 ? Double(tq.powerWordCount) / Double(totalWords) : 0
                let powerBonus = min(5, Int(powerRatio * 150))  // Capped at +5 (down from +10)
                vocabularyScore = min(100, (vocabularyScore ?? base) + powerBonus)
            }
            // MATTR bonus: blend in lexical sophistication from SpeechScoringEngine
            // MATTR is length-invariant and more reliable than simple TTR
            if let em = enhancedMetrics {
                // Blend: 60% existing complexity, 40% MATTR-based lexical sophistication
                let mattrBlended = Int(Double(vocabularyScore ?? base) * 0.60 +
                                       Double(em.lexicalSophisticationScore) * 0.40)
                vocabularyScore = max(0, min(100, mattrBlended))
            }
        } else if let em = enhancedMetrics, em.lexicalSophisticationScore > 0 {
            // No vocabComplexity available — use lexical sophistication as fallback
            vocabularyScore = em.lexicalSophisticationScore
        }

        // Structure score — enhanced with rhetorical devices + transition variety
        var structureScore = sentenceAnalysis?.structureScore
        if let base = structureScore, let tq = textQuality {
            let rhetoricBonus = min(12, tq.rhetoricalDeviceCount * 4)
            let transitionBonus = min(8, Int(Double(tq.transitionVariety) * 0.8))
            let concisenessAdjustment = Int((Double(tq.concisenessScore) - 50.0) * 0.20)
            let engagementAdjustment = Int((Double(tq.engagementScore) - 50.0) * 0.15)
            structureScore = max(0, min(100, base + rhetoricBonus + transitionBonus + concisenessAdjustment + engagementAdjustment))
        }

        return SpeechSubscores(
            clarity: stabilizedClarity,
            pace: stabilizedPace,
            fillerUsage: stabilizedFiller,
            pauseQuality: stabilizedPause,
            vocalVariety: vocalVarietyScore,
            delivery: deliveryScore,
            vocabulary: vocabularyScore,
            structure: structureScore,
            relevance: relevanceScore
        )
    }

    /// Pause scoring with gentler penalties so beginners aren't crushed by natural hesitations.
    private func calculatePauseScore(
        metadata: [PauseInfo],
        fillerRatio: Double,
        wordsPerMinute: Double,
        targetWPM: Double,
        actualDuration: TimeInterval
    ) -> Int {
        guard !metadata.isEmpty else {
            return wordsPerMinute > (targetWPM + 20) ? 50 : 65
        }

        var score = 72.0

        let mediumPauses = metadata.filter { $0.duration >= 1.2 && $0.duration < 3.0 }
        let longPauses = metadata.filter { $0.duration >= 3.0 }

        let strategicMediumCount = mediumPauses.filter { $0.isTransition }.count
        let strategicLongCount = longPauses.filter { $0.isTransition }.count
        score += Double(strategicMediumCount) * 4.0
        score += Double(strategicLongCount) * 6.0

        // Softer hesitation penalty (was -15 per long hesitation)
        let hesitationLongCount = longPauses.filter { !$0.isTransition }.count
        score -= Double(min(hesitationLongCount, 4)) * 8.0

        if fillerRatio < 0.03 && metadata.count > 2 {
            score += 8.0
        }

        let pausesPerMinute = Double(metadata.count) / max(1, actualDuration / 60)
        if pausesPerMinute < 3 {
            score -= 6.0
        } else if pausesPerMinute > 18 {
            score -= (pausesPerMinute - 18) * 1.5
        }

        if wordsPerMinute > (targetWPM + 10) {
            score += Double(strategicMediumCount + strategicLongCount) * 2.0
        }

        return max(0, min(100, Int(score)))
    }

    private func calculateOverallScore(subscores: SpeechSubscores, weights: ScoreWeights = .defaults) -> Int {
        let w = weights.normalized
        var weighted = Double(subscores.clarity) * w.clarity +
                       Double(subscores.pace) * w.pace +
                       Double(subscores.fillerUsage) * w.filler +
                       Double(subscores.pauseQuality) * w.pause

        var totalWeight = w.clarity + w.pace + w.filler + w.pause

        if let vocalVariety = subscores.vocalVariety {
            weighted += Double(vocalVariety) * w.vocalVariety
            totalWeight += w.vocalVariety
        }
        if let delivery = subscores.delivery {
            weighted += Double(delivery) * w.delivery
            totalWeight += w.delivery
        }
        if let vocabulary = subscores.vocabulary {
            weighted += Double(vocabulary) * w.vocabulary
            totalWeight += w.vocabulary
        }
        if let structure = subscores.structure {
            weighted += Double(structure) * w.structure
            totalWeight += w.structure
        }
        if let relevance = subscores.relevance {
            weighted += Double(relevance) * w.relevance
            totalWeight += w.relevance
        }

        guard totalWeight > 0 else { return 0 }
        let score = weighted / totalWeight
        return max(0, min(100, Int(score)))
    }

    // MARK: - LLM Enhancement

    /// Post-analysis step: re-evaluate coherence with LLM blending, enhance structure/vocabulary
    /// with transcript quality evaluation, and recalculate overall score.
    /// `promptText` enables prompt-aware coherence scoring for prompted sessions.
    func enhanceWithLLM(
        analysis: inout SpeechAnalysis,
        transcript: String,
        llmService: LLMService,
        promptText: String? = nil,
        scoreWeights: ScoreWeights = .defaults
    ) async {
        guard llmService.isAvailable, transcript.count >= 25 else { return }
        let backend = llmService.activeBackend
        let baselineSubscores = analysis.speechScore.subscores
        let baselineOverall = analysis.speechScore.overall

        let componentMaxDelta: Int
        let overallMaxDelta: Int
        switch backend {
        case .appleIntelligence:
            componentMaxDelta = 20
            overallMaxDelta = 14
        case .localLLM:
            componentMaxDelta = 16
            overallMaxDelta = 10
        case .none:
            return
        }

        // 1. Enhanced coherence scoring (prompt-aware)
        if let enhancedCoherence = await PromptRelevanceService.coherenceScore(
            transcript: transcript,
            llmService: llmService,
            promptText: promptText
        ) {
            let stabilized = stabilizedLLMScore(
                baseline: baselineSubscores.relevance ?? analysis.promptRelevanceScore ?? 50,
                candidate: enhancedCoherence,
                maxDelta: componentMaxDelta
            )
            analysis.promptRelevanceScore = stabilized
            analysis.speechScore.subscores.relevance = stabilized
        }

        // 2. Transcript quality evaluation (structure + vocabulary)
        if let quality = await llmService.evaluateTranscriptQuality(transcript: transcript) {
            // Blend LLM scores with existing rule-based subscores.
            // Increased blend so active models have a perceptible impact.
            let llmWeight: Double = llmService.activeBackend == .appleIntelligence ? 0.45 : 0.40
            let ruleWeight = 1.0 - llmWeight

            if let existingStructure = analysis.speechScore.subscores.structure {
                let blended = Double(quality.structure) * llmWeight + Double(existingStructure) * ruleWeight
                analysis.speechScore.subscores.structure = stabilizedLLMScore(
                    baseline: existingStructure,
                    candidate: Int(blended.rounded()),
                    maxDelta: componentMaxDelta
                )
            }

            if let existingVocab = analysis.speechScore.subscores.vocabulary {
                let blended = Double(quality.vocabulary) * llmWeight + Double(existingVocab) * ruleWeight
                analysis.speechScore.subscores.vocabulary = stabilizedLLMScore(
                    baseline: existingVocab,
                    candidate: Int(blended.rounded()),
                    maxDelta: componentMaxDelta
                )
            }
        }

        // 3. Recalculate overall score with all updated subscores
        var newOverall = calculateOverallScore(
            subscores: analysis.speechScore.subscores,
            weights: scoreWeights
        )

        // 4. Re-apply substance multiplier after LLM enhancement
        // This ensures LLM cannot inflate scores for gibberish/near-empty speech
        if let em = analysis.enhancedMetrics {
            newOverall = SpeechScoringEngine.applySubstanceMultiplier(
                overallScore: newOverall,
                substanceScore: em.substanceScore
            )
            newOverall = SpeechScoringEngine.applyGibberishGate(
                score: newOverall,
                gibberishConfidence: em.gibberishConfidence
            )
        }

        analysis.speechScore.overall = stabilizedLLMScore(
            baseline: baselineOverall,
            candidate: newOverall,
            maxDelta: overallMaxDelta
        )
    }

    // MARK: - WPM Time Series

    func computeWPMTimeSeries(
        words: [TranscriptionWord],
        actualDuration: TimeInterval,
        windowSize: TimeInterval = 5.0
    ) -> [WPMDataPoint] {
        guard !words.isEmpty, actualDuration > 0 else { return [] }

        var dataPoints: [WPMDataPoint] = []
        var bucketStart: TimeInterval = 0

        while bucketStart < actualDuration {
            let bucketEnd = min(bucketStart + windowSize, actualDuration)
            let bucketDuration = bucketEnd - bucketStart

            // Merge very short trailing buckets into previous to avoid WPM spikes
            if bucketDuration < 2.5 && !dataPoints.isEmpty {
                let prevPoint = dataPoints.removeLast()
                let additionalWords = words.filter { $0.start >= bucketStart && $0.start < bucketEnd }.count
                let totalWords = prevPoint.wordCount + additionalWords
                let combinedDuration = (bucketStart - (prevPoint.timestamp - windowSize / 2.0)) + bucketDuration
                let wpm = combinedDuration > 0 ? Double(totalWords) / (combinedDuration / 60.0) : 0
                let timestamp = prevPoint.timestamp - windowSize / 2.0 + combinedDuration / 2.0

                dataPoints.append(WPMDataPoint(
                    timestamp: timestamp,
                    wpm: wpm,
                    wordCount: totalWords
                ))
                break
            }

            // Count words whose start falls within this bucket
            let wordCount = words.filter { $0.start >= bucketStart && $0.start < bucketEnd }.count

            // Compute WPM for this bucket
            let wpm = bucketDuration > 0 ? Double(wordCount) / (bucketDuration / 60.0) : 0

            // Timestamp is the midpoint of the bucket
            let timestamp = bucketStart + bucketDuration / 2.0

            dataPoints.append(WPMDataPoint(
                timestamp: timestamp,
                wpm: wpm,
                wordCount: wordCount
            ))

            bucketStart += windowSize
        }

        // Smooth with a 3-point moving average to reduce jaggedness
        if dataPoints.count >= 3 {
            var smoothed = dataPoints
            for i in 1..<(dataPoints.count - 1) {
                smoothed[i] = WPMDataPoint(
                    timestamp: dataPoints[i].timestamp,
                    wpm: (dataPoints[i-1].wpm + dataPoints[i].wpm + dataPoints[i+1].wpm) / 3.0,
                    wordCount: dataPoints[i].wordCount
                )
            }
            dataPoints = smoothed
        }

        return dataPoints
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

        // Monotone score: convert dB to linear energy, exclude silence, use CV
        // Raw dB values from AVAudioRecorder are typically -160 to 0.
        // Silence threshold: anything below -40 dB is not speech.
        let speechSamples = samples.filter { $0 > -40 }
        let monotoneScore: Int
        if speechSamples.count >= 4 {
            // Convert dB to linear volume for meaningful variation measurement
            let linearSamples = speechSamples.map { pow(10.0, Double($0) / 20.0) }
            let linMean = linearSamples.reduce(0, +) / Double(linearSamples.count)
            guard linMean > 1e-6 else {
                return VolumeMetrics(averageLevel: average, peakLevel: peak,
                                     dynamicRange: dynamicRange, monotoneScore: 10,
                                     energyScore: 0, levelSamples: samples)
            }
            let linVariance = linearSamples.reduce(0.0) { $0 + pow($1 - linMean, 2) } / Double(linearSamples.count)
            let cv = sqrt(linVariance) / linMean  // Coefficient of variation

            // Map CV to score with calibrated thresholds:
            // CV < 0.15 → monotone (20-40), 0.15-0.35 → moderate (40-70),
            // 0.35-0.60 → good (70-90), > 0.60 → excellent (90-100)
            if cv < 0.15 {
                monotoneScore = 20 + Int(cv / 0.15 * 20)
            } else if cv < 0.35 {
                monotoneScore = 40 + Int((cv - 0.15) / 0.20 * 30)
            } else if cv < 0.60 {
                monotoneScore = 70 + Int((cv - 0.35) / 0.25 * 20)
            } else {
                monotoneScore = min(100, 90 + Int((cv - 0.60) / 0.40 * 10))
            }
        } else {
            monotoneScore = 30 // Not enough speech samples
        }

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

        let longWords = cleaned.filter { $0.count >= 8 }
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

        // Word rarity — delegate to SpeechScoringEngine.computeWordRarityScore to avoid
        // duplicating the NLEmbedding lookup that already runs in the enhanced scoring pipeline.
        let rarityComponent: Double = SpeechScoringEngine.computeWordRarityScore(words: Array(uniqueWords)) * 20.0

        // Composite score with calibrated thresholds for conversational speech
        let uniqueComponent = min(1.0, uniqueRatio / 0.65) * 35
        let repeatPenalty = min(1.0, Double(repeatedPhrases.count) / 5.0)
        let repeatComponent = (1.0 - repeatPenalty) * 20

        // Word diversity bonus: reward using words of varied lengths
        let lengthBuckets = Set(cleaned.map { min($0.count, 10) })
        let diversityScore = min(1.0, Double(lengthBuckets.count) / 7.0) * 25

        let score = min(100, max(0, Int(uniqueComponent + rarityComponent + repeatComponent + diversityScore)))

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

    func analyzeSentenceStructure(words: [TranscriptionWord]) -> SentenceAnalysis {
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

        var score = 60  // Start at 60 base (neutral)

        // Penalties (up to -40)
        score -= Int(incompleteRatio * 20)
        score -= Int(restartRatio * 20)
        score -= min(20, runOnPenalty * 10)

        // Rewards (up to +40)
        // 1. Sentence variety: std dev of lengths between 3-12 is good (+10)
        let lengthStdDev = standardDeviation(sentenceLengths.map { Double($0) })
        if lengthStdDev >= 3 && lengthStdDev <= 12 { score += 10 }

        // 2. Good average length: 8-25 words is ideal (+10)
        if avgLength >= 8 && avgLength <= 25 { score += 10 }
        else if avgLength >= 5 && avgLength <= 30 { score += 5 }

        // 3. Has opening AND closing sentence of reasonable length (+10)
        if totalSentences >= 3 {
            let firstLen = sentenceLengths[0]
            let lastLen = sentenceLengths[totalSentences - 1]
            if firstLen >= 5 && lastLen >= 5 { score += 10 }
        }

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

    // MARK: - Structure Helpers

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
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
                isVocabWord: true,
                isPrimarySpeaker: word.isPrimarySpeaker,
                speakerConfidence: word.speakerConfidence
            )
        }
    }

    // MARK: - Rate Variation Analysis

    func analyzeRateVariation(words: [TranscriptionWord], actualDuration: TimeInterval) -> RateVariationMetrics {
        guard words.count >= 10, actualDuration > 5 else { return RateVariationMetrics() }

        let windowSize: TimeInterval = 10.0
        let hopSize: TimeInterval = 5.0
        var windowedWPMs: [Double] = []

        var windowStart: TimeInterval = 0
        while windowStart + windowSize <= actualDuration {
            let windowEnd = windowStart + windowSize
            let wordsInWindow = words.filter { $0.start >= windowStart && $0.start < windowEnd && !$0.isFiller }
            let wpm = Double(wordsInWindow.count) / (windowSize / 60.0)
            if wpm > 0 { windowedWPMs.append(wpm) }
            windowStart += hopSize
        }

        guard windowedWPMs.count >= 2 else { return RateVariationMetrics() }

        let mean = windowedWPMs.reduce(0, +) / Double(windowedWPMs.count)
        let variance = windowedWPMs.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(windowedWPMs.count)
        let stddev = sqrt(variance)
        let cv = mean > 0 ? stddev / mean : 0
        let rateRange = (windowedWPMs.max() ?? 0) - (windowedWPMs.min() ?? 0)

        // Note: SpeechScoringEngine also computes articulationRate for fluency scoring.
        // This instance feeds RateVariationMetrics which is displayed in the Vocal Variety UI section.
        let totalSpeechTime = words.reduce(0.0) { $0 + $1.duration }
        let articulationRate = totalSpeechTime > 0 ? Double(words.count) / (totalSpeechTime / 60.0) : 0

        // Smooth Gaussian: ideal CV ~0.15, sigma=0.08
        let idealCV = 0.15
        let sigmaCv = 0.08
        let variationScore = max(0, min(100, 15 + Int(85.0 * exp(-pow(cv - idealCV, 2) / (2 * sigmaCv * sigmaCv)))))

        return RateVariationMetrics(
            rateCV: cv,
            articulationRate: articulationRate,
            rateRange: rateRange,
            windowedWPMs: windowedWPMs,
            rateVariationScore: variationScore
        )
    }

    // MARK: - Emphasis Detection

    func analyzeEmphasis(
        words: [TranscriptionWord],
        actualDuration: TimeInterval,
        pitchContour: [Float]? = nil,
        audioLevelSamples: [Float] = []
    ) -> EmphasisMetrics {
        guard words.count >= 5, actualDuration > 0 else { return EmphasisMetrics() }

        let nonFillerWords = words.filter { !$0.isFiller }
        guard nonFillerWords.count >= 3 else { return EmphasisMetrics() }

        var emphasisPositions: [Double] = []

        // Signal-based emphasis detection when pitch/volume data available
        let useSignalDetection = pitchContour != nil && !audioLevelSamples.isEmpty
        if useSignalDetection, let contour = pitchContour, !audioLevelSamples.isEmpty {
            // Build moving averages for pitch and volume
            let pitchWindowSize = max(1, contour.count / 20)
            let volWindowSize = max(1, audioLevelSamples.count / 20)

            for word in nonFillerWords {
                let wordMidpoint = word.start + word.duration / 2.0
                let normalizedPos = wordMidpoint / actualDuration

                // Map word position to contour/level indices
                let pitchIdx = min(contour.count - 1, max(0, Int(normalizedPos * Double(contour.count))))
                let volIdx = min(audioLevelSamples.count - 1, max(0, Int(normalizedPos * Double(audioLevelSamples.count))))

                // Local moving average for pitch
                let pitchStart = max(0, pitchIdx - pitchWindowSize)
                let pitchEnd = min(contour.count, pitchIdx + pitchWindowSize + 1)
                let pitchSlice = contour[pitchStart..<pitchEnd]
                let pitchLocalAvg = pitchSlice.reduce(Float(0), +) / Float(pitchSlice.count)

                // Local moving average for volume
                let volStart = max(0, volIdx - volWindowSize)
                let volEnd = min(audioLevelSamples.count, volIdx + volWindowSize + 1)
                let volSlice = audioLevelSamples[volStart..<volEnd]
                let volLocalAvg = volSlice.reduce(Float(0), +) / Float(volSlice.count)

                let pitchSpike = pitchLocalAvg > 0 ? contour[pitchIdx] / pitchLocalAvg : 1.0
                let volSpike = volLocalAvg < -60 ? Float(1.0) : audioLevelSamples[volIdx] / volLocalAvg

                if pitchSpike > 1.2 && volSpike > 1.2 {
                    emphasisPositions.append(normalizedPos)
                }
            }
        }

        // Fallback: duration-based emphasis detection
        if emphasisPositions.isEmpty {
            let durations = nonFillerWords.map { $0.duration }.filter { $0 > 0 }
            guard !durations.isEmpty else { return EmphasisMetrics() }
            let meanDur = durations.reduce(0, +) / Double(durations.count)
            let variance = durations.reduce(0.0) { $0 + pow($1 - meanDur, 2) } / Double(durations.count)
            let stdDur = sqrt(variance)
            let emphasisThreshold = meanDur + stdDur * 1.2

            for (index, word) in words.enumerated() {
                guard !word.isFiller, word.duration > emphasisThreshold else { continue }

                let pauseBefore = index > 0 ? (word.start - words[index - 1].end) > 0.2 : true
                let pauseAfter = index < words.count - 1 ? (words[index + 1].start - word.end) > 0.2 : true

                if pauseBefore || pauseAfter {
                    emphasisPositions.append(word.start / actualDuration)
                }
            }
        }

        let emphasisCount = emphasisPositions.count
        let emphasisPerMinute = actualDuration > 0 ? Double(emphasisCount) / (actualDuration / 60.0) : 0

        let distributionScore: Int
        if emphasisCount <= 1 {
            distributionScore = 30
        } else {
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

    func analyzeEnergyArc(samples: [Float], words: [TranscriptionWord], actualDuration: TimeInterval) -> EnergyArcMetrics {
        guard !samples.isEmpty, actualDuration > 5 else { return EnergyArcMetrics() }

        // Smooth samples with a moving average to reduce noise
        let smoothWindowSize = max(1, samples.count / 20)
        let smoothed: [Float] = (0..<samples.count).map { i in
            let start = max(0, i - smoothWindowSize / 2)
            let end = min(samples.count, i + smoothWindowSize / 2 + 1)
            let slice = samples[start..<end]
            return slice.reduce(Float(0), +) / Float(slice.count)
        }

        // Convert to linear energy for analysis
        let linearEnergy = smoothed.map { pow(10.0, Double($0) / 20.0) }
        guard !linearEnergy.isEmpty else { return EnergyArcMetrics() }

        // Find actual peak position
        let peakIdx = linearEnergy.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let peakPosition = Double(peakIdx) / Double(linearEnergy.count) // 0.0-1.0

        // Opening/body/closing energy (thirds for reporting)
        let thirdSize = max(1, linearEnergy.count / 3)
        let opening = linearEnergy[0..<thirdSize].reduce(0, +) / Double(thirdSize)
        let body = linearEnergy[thirdSize..<min(thirdSize * 2, linearEnergy.count)].reduce(0, +) / Double(thirdSize)
        let closingSlice = linearEnergy[min(thirdSize * 2, linearEnergy.count)...]
        let closing = closingSlice.isEmpty ? 0 : closingSlice.reduce(0, +) / Double(closingSlice.count)

        let maxEnergy = max(opening, body, closing, 0.001)
        let normOpening = opening / maxEnergy
        let normBody = body / maxEnergy
        let normClosing = closing / maxEnergy

        // Peak detection: is there a clear peak?
        let peakValue = linearEnergy.max() ?? 0
        let avgValue = linearEnergy.reduce(0, +) / Double(linearEnergy.count)
        let hasClearPeak = peakValue > avgValue * 1.3

        // Build-up to peak: energy before peak should generally increase
        let prePeak = Array(linearEnergy[0..<max(1, peakIdx)])
        let prePeakFirstHalf: Double
        let prePeakSecondHalf: Double
        if prePeak.count >= 2 {
            let halfIdx = prePeak.count / 2
            let firstSlice = prePeak[0..<halfIdx]
            let secondSlice = prePeak[halfIdx...]
            prePeakFirstHalf = firstSlice.reduce(0.0, +) / Double(max(1, firstSlice.count))
            prePeakSecondHalf = secondSlice.reduce(0.0, +) / Double(max(1, secondSlice.count))
        } else {
            prePeakFirstHalf = avgValue
            prePeakSecondHalf = avgValue
        }
        let hasBuildUp = prePeakSecondHalf > prePeakFirstHalf * 0.9

        // Resolution after peak: energy should settle but not collapse
        let postPeakStartIdx = min(peakIdx + 1, linearEnergy.count)
        let postPeak = Array(linearEnergy[postPeakStartIdx...])
        let lastPostPeak = postPeak.last ?? 0
        let hasResolution = !postPeak.isEmpty && lastPostPeak > peakValue * 0.3

        var arcScore = 40 // Base
        if hasClearPeak { arcScore += 15 }
        if hasBuildUp { arcScore += 15 }
        if hasResolution { arcScore += 10 }
        if normOpening > 0.6 { arcScore += 10 } // Strong opening
        if normClosing > 0.5 { arcScore += 10 } // Strong finish

        arcScore = max(0, min(100, arcScore))

        let hasClimax = hasClearPeak && peakPosition > 0.3 && peakPosition < 0.85

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

    // MARK: - LLM Score Stabilization

    private func stabilizedLLMScore(baseline: Int, candidate: Int, maxDelta: Int) -> Int {
        let boundedCandidate = max(0, min(100, candidate))
        let delta = boundedCandidate - baseline
        let clampedDelta = max(-maxDelta, min(maxDelta, delta))
        return max(0, min(100, baseline + clampedDelta))
    }
}

// MARK: - Result Types

struct SpeechTranscriptionResult {
    let text: String
    let words: [TranscriptionWord]
    let duration: TimeInterval
    let audioIsolationMetrics: AudioIsolationMetrics?
    let speakerIsolationMetrics: SpeakerIsolationMetrics?
    let voiceProfileUpdate: VoiceProfileUpdate?

    init(
        text: String,
        words: [TranscriptionWord],
        duration: TimeInterval,
        audioIsolationMetrics: AudioIsolationMetrics? = nil,
        speakerIsolationMetrics: SpeakerIsolationMetrics? = nil,
        voiceProfileUpdate: VoiceProfileUpdate? = nil
    ) {
        self.text = text
        self.words = words
        self.duration = duration
        self.audioIsolationMetrics = audioIsolationMetrics
        self.speakerIsolationMetrics = speakerIsolationMetrics
        self.voiceProfileUpdate = voiceProfileUpdate
    }
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

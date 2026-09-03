import Foundation
import Speech
import AVFoundation
import NaturalLanguage
import os

@Observable
class SpeechService {
    private let logger = Logger(subsystem: "com.vansh.SpeakUpMore", category: "Speech")

    // State
    var isTranscribing = false
    var hasPermission = false
    var transcriptionProgress: Double = 0
    var isModelLoaded: Bool { whisperService.isModelLoaded }

    /// Which leg of the fallback chain produced the last transcript. Reported
    /// as a coarse analytics dimension so a rise in Apple Speech fallbacks (a
    /// Whisper regression) is visible without inspecting any transcript.
    private(set) var lastTranscriptionBackend = "unknown"

    // Transcription backend
    private let whisperService = WhisperService()

    // Fallback: Apple Speech recognizer (for when WhisperKit fails)
    private let recognizer: SFSpeechRecognizer?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Main-Actor State

    private func setTranscribingState(isTranscribing: Bool, progress: Double? = nil) async {
        await MainActor.run {
            self.isTranscribing = isTranscribing
            if let progress {
                self.transcriptionProgress = progress
            }
        }
    }

    // MARK: - Model Loading

    /// Pre-load the Whisper model (call on app launch for better UX)
    func preloadModel() async {
        await whisperService.loadModel(modelVariant: "base")
    }

    /// Unload the Whisper model to free memory (e.g. before the local LLM loads)
    func unloadWhisperModel() async {
        await whisperService.unloadModel()
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

        let authorized = status == .authorized
        await MainActor.run {
            hasPermission = authorized
        }
        return authorized
    }

    // MARK: - Lightweight Transcription (text only, no analysis)

    /// Fast transcription that skips isolation, speaker labeling, and filler detection.
    /// Use for dictation where you only need the raw text.
    func transcribeTextOnly(audioURL: URL, preferredTerms: [String] = []) async throws -> String {
        await setTranscribingState(isTranscribing: true)
        defer {
            Task { await self.setTranscribingState(isTranscribing: false) }
        }
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var causes: [String] = []

        do {
            let primary = try await whisperService.transcribe(audioURL: audioURL, preferredTerms: preferredTerms)
            let text = trim(primary.text)
            if !text.isEmpty {
                return text
            }
            causes.append("whisper: empty transcript")
        } catch {
            causes.append(Self.chainCause(backend: "whisper", error))
            // Retry below (model reload + fallback)
        }

        // Retry once with a fresh model in case WhisperKit got into a bad state.
        await whisperService.unloadModel()
        await whisperService.loadModel(modelVariant: "base")

        do {
            let retry = try await whisperService.transcribe(audioURL: audioURL, preferredTerms: preferredTerms)
            let text = trim(retry.text)
            if !text.isEmpty {
                return text
            }
            causes.append("whisper_reload: empty transcript")
        } catch {
            causes.append(Self.chainCause(backend: "whisper_reload", error))
            // Fall through to Apple Speech fallback.
        }

        let fallback = try await transcribeWithAppleSpeech(audioURL: audioURL)
        let fallbackText = trim(fallback.text)
        guard !fallbackText.isEmpty else {
            throw noSpeechError(causes: causes + ["apple_speech: empty transcript"])
        }
        return fallbackText
    }

    // MARK: - Fallback Cause Tracking

    /// UserInfo key carrying the joined fallback-chain causes. Purely
    /// diagnostic — `localizedDescription` stays the stable user-facing string.
    private static let fallbackCausesKey = "SpeechService.fallbackCauses"

    /// One link of the fallback chain: backend tag + error domain#code,
    /// matching the codes-only diagnostics pattern LLMService uses. Message
    /// text stays out so the userInfo string carries no user content.
    private static func chainCause(backend: String, _ error: Error) -> String {
        let nsError = error as NSError
        return "\(backend): \(nsError.domain)#\(nsError.code)"
    }

    /// Terminal "no speech" failure: logs the accumulated chain and embeds it
    /// in userInfo so a bare "No speech detected" stays diagnosable.
    private func noSpeechError(causes: [String]) -> SpeechServiceError {
        logger.error("Speech fallback chain exhausted: \(causes.joined(separator: " | "), privacy: .private(mask: .hash))")
        return .transcriptionFailed(
            NSError(
                domain: "SpeechService",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "No speech detected in recording.",
                    Self.fallbackCausesKey: causes.joined(separator: " | ")
                ]
            )
        )
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        fillerConfig: FillerWordConfig = .default,
        preferredTerms: [String] = [],
        voiceProfile: VoiceProfile? = nil
    ) async throws -> SpeechTranscriptionResult {
        await setTranscribingState(isTranscribing: true, progress: 0)

        defer {
            Task {
                await self.setTranscribingState(isTranscribing: false, progress: 1.0)
            }
        }

        let preparation = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Decode only what isolation preprocess needs here; speaker
                // labeling / pitch analysis decode again post-transcription
                // so no PCM stays resident during the Whisper pass.
                let monoPCM = MonoPCM.decode(url: audioURL)
                let isolationResult = monoPCM.flatMap {
                    SpeechIsolationService.preprocessIfBeneficial(monoPCM: $0)
                }
                let transcriptionURL = isolationResult?.processedAudioURL ?? audioURL
                continuation.resume(returning: (isolationResult, transcriptionURL))
            }
        }

        let isolationResult = preparation.0
        let transcriptionURL = preparation.1
        let shouldCleanupProcessedFile = transcriptionURL != audioURL

        defer {
            if shouldCleanupProcessedFile {
                try? FileManager.default.removeItem(at: transcriptionURL)
            }
        }

        let result: SpeechTranscriptionResult = try await transcribeWithFallbacks(
            preferredURL: transcriptionURL,
            originalURL: audioURL,
            preferredTerms: preferredTerms
        )
        await MainActor.run {
            transcriptionProgress = whisperService.transcriptionProgress
        }

        let postProcessed: SpeechTranscriptionResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
                // Speaker acoustics from the raw capture — isolation preprocess can
                // flatten energy/F0 and mis-label the primary speaker.
                // Reuses the PCM decoded once at the top of `transcribe`; no
                // decode happens when `labelPrimarySpeaker` gates out short takes.
                let speakerLabeled = ConversationIsolationService.labelPrimarySpeaker(
                    words: finalWords,
                    audioURL: audioURL,
                    totalDuration: result.duration,
                    persistentProfile: voiceProfile
                )
                finalWords = speakerLabeled.0
                let speakerIsolationMetrics = speakerLabeled.1
                let voiceProfileUpdate = speakerLabeled.2
                // Every word is kept. Speaker isolation only labels words
                // (`isPrimarySpeaker`); dropping the non-primary ones here deleted
                // them from the stored transcript, so the transcript no longer
                // matched the audio — worst in the back half of a solo recording,
                // where natural pitch declination and fading energy pull words away
                // from a voice profile built from the first 12 seconds. `analyze`
                // still applies the primary-speaker gate for scoring, and the detail
                // view renders the labels as speaker turns.
                let outputText = self.transcriptText(
                    from: finalWords,
                    fallback: result.text
                )

                continuation.resume(returning: SpeechTranscriptionResult(
                    text: outputText,
                    words: finalWords,
                    duration: result.duration,
                    audioIsolationMetrics: isolationResult?.metrics,
                    speakerIsolationMetrics: speakerIsolationMetrics,
                    voiceProfileUpdate: voiceProfileUpdate
                ))
            }
        }

        return postProcessed
    }

    /// Whisper → reload retry → original-URL retry (if isolation ran) → Apple Speech.
    /// Treats an empty transcript as failure so over-gated isolation audio cannot
    /// permanently produce a Silent session when the raw recording still has speech.
    private func transcribeWithFallbacks(
        preferredURL: URL,
        originalURL: URL,
        preferredTerms: [String]
    ) async throws -> SpeechTranscriptionResult {
        let trim: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let isUsable: (SpeechTranscriptionResult) -> Bool = { result in
            !trim(result.text).isEmpty || !result.words.isEmpty
        }
        var causes: [String] = []

        do {
            let primary = try await whisperService.transcribe(
                audioURL: preferredURL,
                preferredTerms: preferredTerms
            )
            if isUsable(primary) {
                lastTranscriptionBackend = "whisper"
                return primary
            }
            causes.append("whisper: empty result")
        } catch {
            causes.append(Self.chainCause(backend: "whisper", error))
            // Retry path below.
        }

        // Isolation may have over-suppressed speech — try the raw capture before
        // paying for a model reload.
        if preferredURL != originalURL {
            do {
                let raw = try await whisperService.transcribe(
                    audioURL: originalURL,
                    preferredTerms: preferredTerms
                )
                if isUsable(raw) {
                    lastTranscriptionBackend = "whisper_raw"
                    return raw
                }
                causes.append("whisper_raw: empty result")
            } catch {
                causes.append(Self.chainCause(backend: "whisper_raw", error))
                // Continue to model reload.
            }
        }

        await whisperService.unloadModel()
        await whisperService.loadModel(modelVariant: "base")

        let reloadURL = preferredURL != originalURL ? originalURL : preferredURL
        do {
            let retry = try await whisperService.transcribe(
                audioURL: reloadURL,
                preferredTerms: preferredTerms
            )
            if isUsable(retry) {
                lastTranscriptionBackend = "whisper_reload"
                return retry
            }
            causes.append("whisper_reload: empty result")
        } catch {
            causes.append(Self.chainCause(backend: "whisper_reload", error))
            // Fall through to Apple Speech.
        }

        // Prefer the original file for Apple Speech — it never saw the
        // isolation preprocess and is the closest match to what was recorded.
        let apple = try await transcribeWithAppleSpeech(audioURL: originalURL)
        if isUsable(apple) {
            lastTranscriptionBackend = "apple_speech"
            return apple
        }

        throw noSpeechError(causes: causes + ["apple_speech: empty result"])
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

        // Unconditional: on-device processing is a product guarantee, not a
        // preference, and `supportsOnDeviceRecognition` can read false while
        // assets are still installing. This was the one leg of the chain that
        // left the device at all. Server-side recognition also stops at roughly
        // a minute of audio and returns that prefix as a final result, so a long
        // recording reaching this fallback came back silently truncated.
        request.requiresOnDeviceRecognition = true

        // Thread-safe resume-once gate — the recognition callback and the
        // timeout task race on different queues.
        final class ResumeGate: @unchecked Sendable {
            private var resumed = false
            private let lock = NSLock()
            func claim() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if resumed { return false }
                resumed = true
                return true
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()

            let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error {
                    guard gate.claim() else { return }
                    continuation.resume(throwing: SpeechServiceError.transcriptionFailed(error))
                    return
                }

                guard let result, result.isFinal else { return }
                guard gate.claim() else { return }

                let transcription = self?.processAppleTranscription(result) ?? SpeechTranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    words: [],
                    duration: 0
                )

                continuation.resume(returning: transcription)
            }

            // Apple Speech can stall with no final result and no error, leaking
            // the continuation (and hanging dictation) forever. Force-resume —
            // scaled to the file, since a flat 90 s aborted long recordings that
            // were still being recognized normally.
            let audioDuration = (try? AVAudioFile(forReading: audioURL)).map {
                Double($0.length) / $0.processingFormat.sampleRate
            } ?? 0
            Task {
                try? await Task.sleep(for: .seconds(min(600, max(90, audioDuration * 5))))
                guard gate.claim() else { return }
                recognitionTask.cancel()
                continuation.resume(throwing: SpeechServiceError.transcriptionFailed(
                    NSError(
                        domain: "SpeechService",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Speech recognition timed out"]
                    )
                ))
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
    
    private func transcriptText(from words: [TranscriptionWord], fallback: String) -> String {
        let resolved = words
            .map(\.word)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? fallback : resolved
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
        var newOverall = SpeechAnalysisPipeline.calculateOverallScore(
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
        analysis.llmEnhancedAt = Date()
    }

    // MARK: - WPM Time Series

    /// Implementation lives in `SpeechAnalysisPipeline`; this wrapper stays
    /// because the detail view builds playback charts off a bare service.
    func computeWPMTimeSeries(
        words: [TranscriptionWord],
        actualDuration: TimeInterval,
        windowSize: TimeInterval = 15.0
    ) -> [WPMDataPoint] {
        SpeechAnalysisPipeline.computeWPMTimeSeries(
            words: words,
            actualDuration: actualDuration,
            windowSize: windowSize
        )
    }

    // MARK: - LLM Score Stabilization

    private func stabilizedLLMScore(baseline: Int, candidate: Int, maxDelta: Int) -> Int {
        let boundedCandidate = max(0, min(100, candidate))
        let delta = boundedCandidate - baseline
        let clampedDelta = max(-maxDelta, min(maxDelta, delta))
        return max(0, min(100, baseline + clampedDelta))
    }
}

// MARK: - Scoring Pipeline

/// The transcription-to-`SpeechAnalysis` scoring pipeline as pure statics.
///
/// Isolation comes from the TYPE under the project's MainActor default, so
/// these steps were silently main-bound no matter which queue invoked them —
/// the coordinator's old GCD bridge compiled clean and still hopped. Every
/// member here is pure value math over PODs, so the whole enum opts out with
/// one `nonisolated` and the coordinator can detach the leg outright.
nonisolated enum SpeechAnalysisPipeline {

    // MARK: - Analysis

    static func analyze(
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
        let unsortedFillerWords: [FillerWord] = fillerCounts.map { entry in
            let value = entry.value
            return FillerWord(
                word: entry.key,
                count: value.count,
                timestamps: value.timestamps,
                kind: .filler
            )
        }

        // Structural repetition (anaphora-as-tic) — same FillerWord shape so
        // the existing filler chips/UI light up without a second render path.
        // Honor trackFillerWords: off means no filler-shaped feedback at all.
        // Uses scoringWords (already primary-speaker filtered when diarization
        // applied), so interviewer/coach turns never contribute.
        let structuralHits = trackFillerWords
            ? StructuralRepetitionDetector.detect(in: scoringWords)
            : []
        let mergedFillers = mergeFillerWords(unsortedFillerWords + structuralHits)
        let fillerWords: [FillerWord] = mergedFillers.sorted { lhs, rhs in
            // Dictionary iteration order is undefined. Count ties need a
            // stable key or identical analyses can reorder rows between runs.
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.word < rhs.word
        }

        let totalFillers = fillerWords.reduce(0) { $0 + $1.count }
        let scoringDuration = effectiveSpeechDuration(words: scoringWords, fallback: actualDuration)
        // WPM is the gross speech rate the user sees: total words over the full recording
        // duration. Using scoringDuration here (active speech window) inflated the number
        // whenever there was pre/post-speech dead time — e.g. 135 words in a 50s clip where
        // the user started speaking 9s in would report ~254 WPM instead of the correct 162.
        let wpmDuration = max(actualDuration, 1.0)
        let wordsPerMinute = Double(totalWords) / (wpmDuration / 60)

        let pauses = pauseMetadata.map { $0.duration }
        // Mean over pauses ≤ 5 s; gaps longer than that are recording artifacts, not speech pauses.
        // Median was tried but skews too low when many micro-gaps (0.4–0.7 s) outnumber intentional pauses.
        let averagePauseLength: Double
        if pauses.isEmpty {
            averagePauseLength = 0
        } else {
            let sample = pauses.filter { $0 <= 5.0 }
            let relevant = sample.isEmpty ? pauses : sample
            averagePauseLength = relevant.reduce(0, +) / Double(relevant.count)
        }

        // Count strategic vs hesitation pauses
        let strategicPauseCount = pauseMetadata.filter { $0.isTransition }.count
        let hesitationPauseCount = pauseMetadata.filter { !$0.isTransition && $0.duration > 1.2 }.count

        // Run sub-analyses
        let volumeMetrics = !audioLevelSamples.isEmpty ? analyzeVolume(samples: audioLevelSamples) : nil
        let vocabComplexity = !scoringWords.isEmpty ? analyzeVocabComplexity(words: scoringWords) : nil
        let sentenceAnalysis = !scoringWords.isEmpty ? analyzeSentenceStructure(words: scoringWords) : nil

        // Advanced analyses — decode the take for pitch scoring.
        let pitchMetrics: PitchMetrics? = audioURL.flatMap {
            MonoPCM.decode(url: $0)
        }.flatMap { PitchAnalysisService.analyze(monoPCM: $0) }
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
        let vocabWordsUsed = VocabMatcher.usages(in: scoringText, vocabWords: vocabWords)

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
        // Graduated 5-signal confidence (0–1) from SpeechScoringEngine.
        overallScore = SpeechScoringEngine.applyGibberishGate(
            score: overallScore,
            gibberishConfidence: enhancedMetrics.gibberishConfidence
        )

        let clarity = Double(subscores.clarity)

        // Compute WPM time series
        let wpmTimeSeries = computeWPMTimeSeries(words: scoringWords, actualDuration: wpmDuration)

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

    /// Collapse duplicate filler labels (classic fillers + structural frames)
    /// into one row per word+kind with combined counts and timestamps.
    private static func mergeFillerWords(_ items: [FillerWord]) -> [FillerWord] {
        var aggregates: [String: (word: String, kind: FillerHitKind, count: Int, timestamps: [TimeInterval])] = [:]
        for item in items {
            let key = "\(item.kind.rawValue)\u{1f}\(item.word.lowercased())"
            var entry = aggregates[key]
                ?? (word: item.word.lowercased(), kind: item.kind, count: 0, timestamps: [])
            entry.count += item.count
            entry.timestamps.append(contentsOf: item.timestamps)
            aggregates[key] = entry
        }
        return aggregates.map { _, value in
            FillerWord(
                word: value.word,
                count: value.count,
                timestamps: value.timestamps.sorted(),
                kind: value.kind
            )
        }
    }

    private static func contentDensityScore(words: [TranscriptionWord]) -> Int {
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

    private static func effectiveSpeechDuration(words: [TranscriptionWord], fallback: TimeInterval) -> TimeInterval {
        guard let first = words.first, let last = words.last else { return fallback }
        let activeWindow = max(0, last.end - first.start)
        return max(activeWindow, min(fallback, 5.0))
    }

    private static func applyReliabilityStabilization(score: Int, reliability: Double, neutralAnchor: Int) -> Int {
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

    private static func combinedReliabilityScore(
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

    private static func shouldScoreUsingPrimarySpeakerWords(
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


    // MARK: - Subscore Calculation

    private static func calculateSubscores(
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

        // Clarity score — blends two articulation signals (voiced-frame ratio and ASR confidence)
        // with duration steadiness, authority, and a small hedge/pace adjustment. Calibrated so
        // a typical conversational session (VFR 0.30, avgConf 0.78, CV 0.70, authority 70) lands
        // in the low-80s, while mumbled delivery stays below 60 and strong delivery reaches 90+.
        let clarityScore: Int
        do {
            let hasVFR = (pitchMetrics?.voicedFrameRatio ?? 0) > 0
            let confidences = words.compactMap { $0.confidence }
            let hasConfidence = !confidences.isEmpty

            let articulationFromVFR: Double
            if let pm = pitchMetrics, pm.voicedFrameRatio > 0 {
                articulationFromVFR = min(100, max(0, Double(pm.voicedFrameRatio) * 140 + 55))
            } else {
                articulationFromVFR = 70
            }

            let asrConfidenceScore: Double
            if hasConfidence {
                let averageConfidence = confidences.reduce(0, +) / Double(confidences.count)
                asrConfidenceScore = min(100, max(0, averageConfidence * 120 - 10))
            } else {
                asrConfidenceScore = 70
            }

            let durations = words.map { $0.duration }.filter { $0 > 0 }
            let durationScore: Double
            if durations.count >= 2 {
                let meanDur = durations.reduce(0, +) / Double(durations.count)
                let variance = durations.reduce(0.0) { $0 + pow($1 - meanDur, 2) } / Double(durations.count)
                let cv = meanDur > 0 ? sqrt(variance) / meanDur : 1.0
                durationScore = max(0, min(100, (1.0 - cv * 0.35) * 100))
            } else {
                durationScore = 70
            }

            let authorityComponent: Double
            let hedgePenalty: Double
            if let tq = textQuality {
                authorityComponent = Double(tq.authorityScore)
                hedgePenalty = min(12, tq.hedgeWordRatio * 180)
            } else {
                authorityComponent = 70
                hedgePenalty = 0
            }

            // Redistribute weight when one articulation source is unavailable so the absent
            // component doesn't silently drop 25-30% of the score.
            let vfrWeight: Double
            let asrWeight: Double
            switch (hasVFR, hasConfidence) {
            case (true, true):   vfrWeight = 0.30; asrWeight = 0.25
            case (true, false):  vfrWeight = 0.55; asrWeight = 0.00
            case (false, true):  vfrWeight = 0.00; asrWeight = 0.55
            case (false, false): vfrWeight = 0.30; asrWeight = 0.25
            }

            let paceAlignmentBonus = max(0, 5 - abs(wordsPerMinute - Double(targetWPM)) / 20)
            let rawClarity = articulationFromVFR * vfrWeight +
                asrConfidenceScore * asrWeight +
                durationScore * 0.15 +
                authorityComponent * 0.15 +
                (100 - hedgePenalty) * 0.05 +
                paceAlignmentBonus
            clarityScore = max(0, min(100, Int(rawClarity.rounded())))
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

        // Clarity uses a higher anchor (65) because its newly calibrated range centers on ~80 for
        // typical speech — pulling toward 55 would punish any moderately-reliable solo recording.
        let stabilizedClarity = applyReliabilityStabilization(
            score: clarityScore,
            reliability: combinedReliability,
            neutralAnchor: 65
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
    private static func calculatePauseScore(
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

    static func calculateOverallScore(subscores: SpeechSubscores, weights: ScoreWeights = .defaults) -> Int {
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


    // MARK: - WPM Time Series

    /// Speaking rate over a **sliding 15-second window**, stepped a third of a
    /// window so consecutive points overlap.
    ///
    /// Disjoint 5-second buckets measured articulation rate, not pace: any
    /// bucket that happened to land inside one fluent run reported words/minute
    /// as if the speaker never breathed. A take with 45% silence and a normal
    /// 5 words/sec delivery — a gross rate of 170 WPM — peaked at 300 on the
    /// chart, and the 3-point moving average could not save it because the
    /// first and last buckets were never smoothed. Fifteen seconds always
    /// contains breaths, so a window reads the rate the user actually spoke at
    /// and the peaks stay near the headline average.
    ///
    /// The window shrinks on short takes (never more than a third of the clip,
    /// floor 5s) so a 30-second session still gets a curve rather than a dot.
    /// Overlapping windows are self-smoothing — the moving average is gone.
    static func computeWPMTimeSeries(
        words: [TranscriptionWord],
        actualDuration: TimeInterval,
        windowSize: TimeInterval = 15.0
    ) -> [WPMDataPoint] {
        guard !words.isEmpty, actualDuration > 0 else { return [] }

        let window = min(actualDuration, max(5.0, min(windowSize, actualDuration / 3)))
        let step = window / 3
        let lastStart = max(0, actualDuration - window)

        // Window starts, with the final one flush to the end of the take so the
        // chart covers it. The half-step guard keeps that flush window from
        // landing on top of the one before it.
        var starts: [TimeInterval] = []
        var cursor: TimeInterval = 0
        while cursor < lastStart - step / 2 {
            starts.append(cursor)
            cursor += step
        }
        starts.append(lastStart)

        return starts.map { start in
            let end = start + window
            let wordCount = words.filter { $0.start >= start && $0.start < end }.count
            return WPMDataPoint(
                timestamp: start + window / 2,
                wpm: Double(wordCount) / (window / 60.0),
                wordCount: wordCount
            )
        }
    }


    // MARK: - Volume Analysis

    // MARK: - Vocabulary Complexity Analysis

    // MARK: - Sentence Structure Analysis

    // MARK: - Structure Helpers

    // MARK: - Rate Variation Analysis

    // MARK: - Emphasis Detection

    // MARK: - Energy Arc Analysis


    nonisolated static func analyzeVolume(samples: [Float]) -> VolumeMetrics {
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

    nonisolated static func analyzeVocabComplexity(words: [TranscriptionWord]) -> VocabComplexity {
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

    nonisolated static func analyzeSentenceStructure(words: [TranscriptionWord]) -> SentenceAnalysis {
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

    nonisolated static func analyzeRateVariation(words: [TranscriptionWord], actualDuration: TimeInterval) -> RateVariationMetrics {
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

    nonisolated static func analyzeEmphasis(
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
                // Levels are dB (negative) — a ratio inverts the comparison.
                // Use a dB difference: 6 dB above the local average = emphasis.
                let volSpikeDb = volLocalAvg < -60 ? Float(0) : audioLevelSamples[volIdx] - volLocalAvg

                if pitchSpike > 1.2 && volSpikeDb > 6 {
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

    nonisolated static func analyzeEnergyArc(samples: [Float], words: [TranscriptionWord], actualDuration: TimeInterval) -> EnergyArcMetrics {
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

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}

// MARK: - Result Types

nonisolated struct SpeechTranscriptionResult {
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

nonisolated struct PauseInfo {
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

import Foundation
import SwiftData
import WidgetKit
import os

@MainActor
@Observable
final class RecordingProcessingCoordinator {
    static let shared = RecordingProcessingCoordinator()

    /// Ceiling on one resume pass. Someone returning after a long break has a
    /// backlog worth clearing, but not an unbounded one.
    private static let deferredResumeLimit = 20

    private let logger = Logger(subsystem: "com.vansh.SpeakUpMore", category: "RecordingProcessing")
    private var activeRecordingIDs: Set<UUID> = []
    private var resumeInFlight = false

    /// Analyses that cleared the allowance gate but have not been charged yet.
    ///
    /// The gate reads persisted counters and the charge lands minutes later,
    /// after transcription. Nothing serialises two different recordings, so
    /// without this both see the same `remaining` and both go through — a user
    /// with one analysis left who stops two recordings in a row gets two.
    private var reservedAnalyses = 0

    private init() {}

    func isProcessing(_ recordingID: UUID) -> Bool {
        activeRecordingIDs.contains(recordingID)
    }

    func enqueue(
        recordingID: UUID,
        modelContext: ModelContext,
        speechService: SpeechService,
        llmService: LLMService
    ) {
        guard !activeRecordingIDs.contains(recordingID) else { return }
        activeRecordingIDs.insert(recordingID)

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.activeRecordingIDs.remove(recordingID) }
            await self.process(
                recordingID: recordingID,
                modelContext: modelContext,
                speechService: speechService,
                llmService: llmService
            )
        }
    }

    /// Scores the recordings the free allowance held back, oldest first.
    ///
    /// The deferred card tells the user their audio is safe and will score
    /// itself when the allowance resets or Lifetime is unlocked. Nothing kept
    /// that promise before: a held-back recording was only retried if the user
    /// happened to reopen it. Called on foreground and on entitlement change.
    ///
    /// Runs strictly one at a time — a batch of concurrent Whisper passes on a
    /// cold foreground would be a memory spike, not a feature.
    func resumeDeferredRecordings(
        modelContext: ModelContext,
        speechService: SpeechService,
        llmService: LLMService
    ) {
        guard !resumeInFlight else { return }
        guard AllowanceGate.decision(settings: fetchSettings(from: modelContext)).isAllowed else { return }
        resumeInFlight = true

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.resumeInFlight = false }

            // Bounded so a recording that somehow re-defers itself cannot spin.
            for _ in 0..<Self.deferredResumeLimit {
                guard AllowanceGate.decision(settings: self.fetchSettings(from: modelContext)).isAllowed else { return }

                var descriptor = FetchDescriptor<Recording>(
                    predicate: #Predicate { $0.analysisBlockedByAllowance == true },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
                // Fetch a window rather than one row so a deferred recording the
                // user is already retrying by hand is stepped over instead of
                // ending the whole pass and stranding the backlog behind it.
                descriptor.fetchLimit = Self.deferredResumeLimit
                guard let next = (try? modelContext.fetch(descriptor))?
                    .first(where: { !self.activeRecordingIDs.contains($0.id) }) else { return }

                let id = next.id
                self.activeRecordingIDs.insert(id)
                await self.process(
                    recordingID: id,
                    modelContext: modelContext,
                    speechService: speechService,
                    llmService: llmService
                )
                self.activeRecordingIDs.remove(id)

                // Re-fetch rather than reuse `next`: processing can take minutes
                // and the user may have deleted it meanwhile. A recording still
                // flagged deferred means the allowance ran out mid-run, so stop;
                // a deleted one just means move on.
                var check = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
                check.fetchLimit = 1
                if let after = (try? modelContext.fetch(check))?.first,
                   after.analysisBlockedByAllowance {
                    return
                }
            }
        }
    }

    private func process(
        recordingID: UUID,
        modelContext: ModelContext,
        speechService: SpeechService,
        llmService: LLMService
    ) async {
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == recordingID }
        )

        guard let recording = fetchRecording(with: descriptor, modelContext: modelContext) else { return }

        if recording.analysis != nil {
            if recording.isProcessing {
                recording.isProcessing = false
                save(modelContext, context: "clearing processing flag for pre-analyzed recording \(recordingID.uuidString)")
            }
            return
        }

        guard let mediaURL = recording.resolvedAudioURL ?? recording.resolvedVideoURL else {
            recording.isProcessing = false
            recording.lastProcessingError = "Audio file is missing."
            save(modelContext, context: "clearing processing flag for missing media \(recordingID.uuidString)")
            return
        }

        // Newly promoted iCloud files can briefly report a non-current download
        // status; kick the download and wait a beat before giving up.
        if !FileManager.default.fileExists(atPath: mediaURL.path)
            || !ICloudStorageService.shared.isFileDownloaded(at: mediaURL) {
            ICloudStorageService.shared.ensureDownloaded(at: mediaURL)
            for _ in 0..<10 {
                if FileManager.default.fileExists(atPath: mediaURL.path),
                   ICloudStorageService.shared.isFileDownloaded(at: mediaURL) {
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            recording.isProcessing = false
            recording.lastProcessingError = "Audio file hasn't downloaded from iCloud yet."
            save(modelContext, context: "clearing processing flag for undownloaded media \(recordingID.uuidString)")
            return
        }

        let settings = fetchSettings(from: modelContext)

        // Free-tier gate. Deliberately after the idempotency and media guards:
        // re-opening an already-analyzed recording must never trip it, and a
        // recording with no audio should report the missing file, not a paywall.
        let decision = AllowanceGate.decision(settings: settings)
        // `remaining` is nil while entitled or inside the trial — nothing is
        // being counted there, so nothing needs reserving.
        let chargeable = decision.remaining != nil
        let alreadyReserved = decision.remaining.map { $0 <= reservedAnalyses } ?? false
        guard decision.isAllowed, !alreadyReserved else {
            recording.isProcessing = false
            recording.lastProcessingError = nil
            recording.analysisBlockedByAllowance = true
            save(modelContext, context: "deferring analysis past free allowance \(recordingID.uuidString)")
            AnalyticsService.shared.log(.allowanceExhausted())
            return
        }
        // Held until this call returns, which is after `consume` has persisted
        // the charge on the success path. A failure releases it uncharged.
        if chargeable { reservedAnalyses += 1 }
        defer { if chargeable { reservedAnalyses -= 1 } }

        if recording.analysisBlockedByAllowance {
            recording.analysisBlockedByAllowance = false
        }

        recording.isProcessing = true
        recording.lastProcessingError = nil
        save(modelContext, context: "marking recording processing \(recordingID.uuidString)")

        let startedAt = Date()
        let vocabWords = VocabMatcher.mergeUnique(
            settings?.vocabWords ?? [],
            VocabChallengeService.detectionWords(
                preferences: settings?.vocabChallengePreferences ?? .disabled
            )
        )
        let scoreWeights = ScoreWeights(from: settings)

        do {
            let computed: (SpeechAnalysis, [TranscriptionWord], String?, VoiceProfileUpdate?)
            if let existingText = recording.transcriptionText,
               let existingWords = recording.transcriptionWords,
               !existingWords.isEmpty {
                let analyzed = await analyzeTranscript(
                    transcription: SpeechTranscriptionResult(
                        text: existingText,
                        words: existingWords,
                        duration: recording.actualDuration
                    ),
                    recording: recording,
                    vocabWords: vocabWords,
                    scoreWeights: scoreWeights,
                    settings: settings,
                    promptText: effectivePromptText(for: recording, modelContext: modelContext)
                )
                computed = (analyzed.analysis, analyzed.markedWords, existingText, nil)
            } else {
                let preferredTerms = settings?.transcriptionBiasTerms ?? []
                let fillerConfig = FillerWordConfig(
                    customFillers: Set(settings?.customFillerWords ?? []),
                    customContextFillers: Set(settings?.customContextFillerWords ?? []),
                    removedDefaults: Set(settings?.removedDefaultFillers ?? [])
                )
                let voiceProfile: VoiceProfile? = {
                    guard let f0 = settings?.voiceProfileF0Hz,
                          let energy = settings?.voiceProfileEnergyDb else { return nil }
                    return VoiceProfile(
                        f0Hz: f0,
                        energyDb: energy,
                        sampleCount: settings?.voiceProfileSampleCount ?? 0
                    )
                }()

                if llmService.localLLM.isModelReady {
                    llmService.localLLM.unloadModel()
                }

                // No outer timeout: the Whisper legs self-bound on a decode-stall
                // watchdog and the Apple Speech leg on a duration-scaled timer.
                // An outer race here killed the fallback chain whenever the first
                // attempt used its full window.
                let transcription = try await speechService.transcribe(
                    audioURL: mediaURL,
                    fillerConfig: fillerConfig,
                    preferredTerms: preferredTerms,
                    voiceProfile: voiceProfile
                )

                // Transcription can run for minutes — confirm the recording still exists
                // before touching its properties (deleted SwiftData objects trap).
                guard let persisted = fetchRecording(with: descriptor, modelContext: modelContext) else { return }

                let analyzed = await analyzeTranscript(
                    transcription: transcription,
                    recording: persisted,
                    vocabWords: vocabWords,
                    scoreWeights: scoreWeights,
                    settings: settings,
                    promptText: effectivePromptText(for: persisted, modelContext: modelContext)
                )
                computed = (
                    analyzed.analysis,
                    analyzed.markedWords,
                    transcription.text,
                    transcription.voiceProfileUpdate
                )

                if let settings {
                    applyAutoCalibration(
                        transcription: transcription,
                        analysis: analyzed.analysis,
                        settings: settings
                    )
                }
            }

            // Re-fetch before writing — the user may have deleted the recording
            // while transcription/analysis ran (potentially minutes). Writing to a deleted
            // SwiftData object traps.
            guard let persisted = fetchRecording(with: descriptor, modelContext: modelContext) else { return }
            if let text = computed.2 {
                persisted.transcriptionText = text
            }
            persisted.transcriptionWords = computed.1
            persisted.analysis = computed.0
            // Speaking a tracked word is its review — grade it here so the
            // schedule stays right for users who never open the Today tab.
            VocabChallengeService.recordUsage(
                computed.0.vocabWordsUsed,
                preferences: settings?.vocabChallengePreferences ?? .disabled
            )
            persisted.isProcessing = false
            persisted.lastProcessingError = nil
            persisted.analysisBlockedByAllowance = false
            updateStoryBestScore(for: persisted, modelContext: modelContext)
            // Charged only on success — a failed transcription must not cost a
            // free analysis.
            AllowanceGate.consume(settings: settings)
            save(modelContext, context: "persisting analysis for \(recordingID.uuidString)")
            logCompletion(
                startedAt: startedAt,
                backend: speechService.lastTranscriptionBackend,
                modelContext: modelContext
            )
            // Once per completed recording — keeps widgets fresh for users who
            // record from Library/History and never open the Today tab.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            logger.error("Recording processing failed for \(recordingID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .private(mask: .hash))")
            AnalyticsService.shared.log(.analysisFailed(reason: Self.failureCategory(for: error)))
            guard let persisted = fetchRecording(with: descriptor, modelContext: modelContext) else { return }
            persisted.isProcessing = false
            persisted.lastProcessingError = error.localizedDescription
            save(modelContext, context: "clearing processing flag after error \(recordingID.uuidString)")
        }
    }

    // MARK: - Measurement

    /// Time to value is the launch gate the whole onboarding plan is judged on,
    /// so it is measured where the work actually finishes rather than where the
    /// UI happens to notice.
    private func logCompletion(startedAt: Date, backend: String, modelContext: ModelContext) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let analyzedCount = analyzedRecordingCount(modelContext)

        AnalyticsService.shared.log(
            .analysisCompleted(
                sessionNumber: analyzedCount,
                processingPath: backend,
                elapsed: elapsed
            )
        )
        AnalyticsService.shared.logOnce(
            .activated(minutesFromFirstOpen: AttributionStore.shared.minutesSinceFirstOpen),
            key: "activated"
        )
    }

    /// Counted on `transcriptionText`: SwiftData stores the Codable `analysis`
    /// as a composite attribute with no queryable column, so a predicate on it
    /// raises an ObjC exception inside CoreData's SQL generation — not a Swift
    /// error, so `try?` cannot catch it and the app terminates. Transcript and
    /// analysis persist in the same save, so the two counts agree.
    private func analyzedRecordingCount(_ modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.transcriptionText != nil }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Coarse reason only — an error string can contain a file path.
    private static func failureCategory(for error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("timed out") || text.contains("timeout") { return "timeout" }
        if text.contains("model") { return "model" }
        if text.contains("permission") || text.contains("denied") { return "permission" }
        if text.contains("audio") || text.contains("file") { return "audio" }
        return "other"
    }

    /// Per-recording auto-calibration: every quality-gated session nudges the
    /// voice profile (speaker isolation) and the learned pace target. Runs only
    /// on the fresh-transcription path — re-analyzing the same audio would
    /// double-weight that session in the EMA. Persistence rides the analysis
    /// save that follows.
    private func applyAutoCalibration(
        transcription: SpeechTranscriptionResult,
        analysis: SpeechAnalysis,
        settings: UserSettings
    ) {
        // Never learn from junk sessions.
        guard analysis.enhancedMetrics?.isDefinitelyGibberish != true,
              analysis.speechScore.overall > 0 else { return }

        let conversationDetected = transcription.speakerIsolationMetrics?.conversationDetected ?? false
        let alpha = 0.3

        // Voice profile (speaker isolation). Sourced from voiceProfileUpdate —
        // the same PCM-derived measurement chain its consumer compares against,
        // unlike whole-file pitchMetrics/volumeMetrics.
        if let update = transcription.voiceProfileUpdate,
           !conversationDetected || update.separationConfidence >= 50 {
            if let existingF0 = settings.voiceProfileF0Hz, settings.voiceProfileSampleCount > 0 {
                settings.voiceProfileF0Hz = existingF0 * (1 - alpha) + update.sessionF0Hz * alpha
                // Seed nil energy instead of blending toward 0 dB.
                settings.voiceProfileEnergyDb = settings.voiceProfileEnergyDb.map {
                    $0 * (1 - alpha) + update.sessionEnergyDb * alpha
                } ?? update.sessionEnergyDb
            } else {
                settings.voiceProfileF0Hz = update.sessionF0Hz
                settings.voiceProfileEnergyDb = update.sessionEnergyDb
            }
            settings.voiceProfileSampleCount += 1
            settings.voiceProfileLastUpdated = Date()
        }

        // Learned pace target — EMA of observed WPM, clamped to the coaching
        // band so the target adapts to the speaker without endorsing racing or
        // crawling. Conversations skipped: elapsed-time WPM is distorted when
        // someone else holds the floor.
        if !conversationDetected,
           transcription.duration >= 30,
           analysis.totalWords >= 40,
           (60...260).contains(analysis.wordsPerMinute) {
            let previous = settings.calibratedWPM ?? Double(settings.targetWPM)
            let blended = previous * (1 - alpha) + analysis.wordsPerMinute * alpha
            settings.calibratedWPM = min(max(blended, 110), 190)
        }
    }

    /// Keep the linked story's best score in sync once analysis is available.
    /// `RecordingViewModel.stopRecording()` runs before analysis exists, so the
    /// score half of story stats can only be updated here.
    private func updateStoryBestScore(for recording: Recording, modelContext: ModelContext) {
        guard let storyId = recording.storyId,
              let score = recording.analysis?.speechScore.overall,
              score > 0 else { return }
        var descriptor = FetchDescriptor<Story>(predicate: #Predicate { $0.id == storyId })
        descriptor.fetchLimit = 1
        guard let story = (try? modelContext.fetch(descriptor))?.first,
              score > story.bestScore else { return }
        story.bestScore = score
        story.updatedAt = Date()
    }

    private func analyzeTranscript(
        transcription: SpeechTranscriptionResult,
        recording: Recording,
        vocabWords: [String],
        scoreWeights: ScoreWeights,
        settings: UserSettings?,
        promptText: String?
    ) async -> (analysis: SpeechAnalysis, markedWords: [TranscriptionWord]) {
        let resultSnapshot = transcription
        let actualDuration = recording.actualDuration
        let audioLevelSamples = recording.audioLevelSamples ?? []
        let audioURL = recording.resolvedAudioURL ?? recording.resolvedVideoURL
        let targetWPM = settings.resolvedTargetWPM
        let trackFillerWords = settings?.trackFillerWords ?? true
        let trackPauses = settings?.trackPauses ?? true

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // analyze() never touches the Whisper model; a throwaway
                // instance avoids hopping the MainActor-isolated shared service.
                let analyzer = SpeechService()
                let analysis = analyzer.analyze(
                    transcription: resultSnapshot,
                    actualDuration: actualDuration,
                    vocabWords: vocabWords,
                    audioLevelSamples: audioLevelSamples,
                    audioURL: audioURL,
                    promptText: promptText,
                    targetWPM: targetWPM,
                    trackFillerWords: trackFillerWords,
                    trackPauses: trackPauses,
                    scoreWeights: scoreWeights,
                    audioIsolationMetrics: resultSnapshot.audioIsolationMetrics,
                    speakerIsolationMetrics: resultSnapshot.speakerIsolationMetrics
                )
                let markedWords = analyzer.markVocabWordsInTranscription(
                    resultSnapshot.words,
                    vocabWords: vocabWords
                )
                continuation.resume(returning: (analysis, markedWords))
            }
        }
    }

    private func effectivePromptText(for recording: Recording, modelContext: ModelContext?) -> String? {
        if let storyId = recording.storyId, let modelContext {
            var descriptor = FetchDescriptor<Story>(
                predicate: #Predicate { $0.id == storyId }
            )
            descriptor.fetchLimit = 1
            if let story = (try? modelContext.fetch(descriptor))?.first {
                let trimmed = story.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return recording.prompt?.text
    }

    private func fetchRecording(
        with descriptor: FetchDescriptor<Recording>,
        modelContext: ModelContext
    ) -> Recording? {
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch recording for processing: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return nil
        }
    }

    private func fetchSettings(from modelContext: ModelContext) -> UserSettings? {
        do {
            return try modelContext.fetch(FetchDescriptor<UserSettings>()).first
        } catch {
            logger.error("Failed to fetch user settings for processing: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return nil
        }
    }

    @discardableResult
    private func save(_ modelContext: ModelContext, context: String) -> Bool {
        guard modelContext.hasChanges else { return true }
        do {
            try modelContext.save()
            return true
        } catch {
            logger.error("Failed to save model context (\(context, privacy: .public)): \(error.localizedDescription, privacy: .private(mask: .hash))")
            return false
        }
    }
}

import Foundation
import UIKit
import SwiftData
import WidgetKit
import os

nonisolated enum ProcessingPolicy {
    static let deferredResumeLimit = 20

    struct Reservation: Sendable, Equatable {
        let shouldDefer: Bool
        let holdsReservation: Bool
    }

    static func reservation(
        for decision: AllowanceDecision,
        reservedAnalyses: Int
    ) -> Reservation {
        // `remaining` is nil while entitled or inside the trial — nothing is
        // being counted there, so nothing needs reserving. Exhausted defers
        // and must also stay reservation-free: its remaining == 0 is non-nil,
        // and a recording parked at the gate would otherwise pin a slot it
        // never processes — leaking capacity from future callers' budgets.
        let holdsReservation = decision.isAllowed && decision.remaining != nil
        let alreadyReserved = decision.remaining.map { $0 <= reservedAnalyses } ?? false
        return Reservation(
            shouldDefer: !decision.isAllowed || alreadyReserved,
            holdsReservation: holdsReservation
        )
    }

    static func nextResumeIndex(in orderedIDs: [UUID], skippingActive activeIDs: Set<UUID>) -> Int? {
        orderedIDs.firstIndex(where: { !activeIDs.contains($0) })
    }

    static func stopsResumePass(doesRecordingExist: Bool, stillBlockedByAllowance: Bool) -> Bool {
        doesRecordingExist && stillBlockedByAllowance
    }
}

@MainActor
@Observable
final class RecordingProcessingCoordinator {
    static let shared = RecordingProcessingCoordinator()

    private let logger = Logger.app("RecordingProcessing")
    private var activeRecordingIDs: Set<UUID> = []
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var resumeInFlight = false
    private var resumeTask: Task<Void, Never>?

    private var reservedAnalyses = 0

    private init() {}

    func isProcessing(_ recordingID: UUID) -> Bool {
        activeRecordingIDs.contains(recordingID)
    }

    /// Stops an in-flight analysis and forgets the recording was queued.
    /// deleted recording can never be written to. Deletion flows should call
    /// this BEFORE removing the SwiftData object.
    func cancelProcessing(recordingID: UUID) {
        activeRecordingIDs.remove(recordingID)
        activeTasks.removeValue(forKey: recordingID)?.cancel()
    }

    func enqueue(
        recordingID: UUID,
        modelContext: ModelContext,
        speechService: SpeechService,
        llmService: LLMService
    ) {
        guard !activeRecordingIDs.contains(recordingID) else { return }
        activeRecordingIDs.insert(recordingID)

        let job = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.activeRecordingIDs.remove(recordingID)
                self.activeTasks[recordingID] = nil
            }
            await self.process(
                recordingID: recordingID,
                modelContext: modelContext,
                speechService: speechService,
                llmService: llmService
            )
        }
        activeTasks[recordingID] = job
    }

    func resumeDeferredRecordings(
        modelContext: ModelContext,
        speechService: SpeechService,
        llmService: LLMService
    ) {
        guard !resumeInFlight else { return }
        guard AllowanceGate.decision(settings: fetchSettings(from: modelContext)).isAllowed else { return }
        resumeInFlight = true

        let pass = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.resumeInFlight = false }

            // Bounded so a recording that somehow re-defers itself cannot spin.
            for _ in 0..<ProcessingPolicy.deferredResumeLimit {
                guard AllowanceGate.decision(settings: self.fetchSettings(from: modelContext)).isAllowed else { return }

                var descriptor = FetchDescriptor<Recording>(
                    predicate: #Predicate { $0.analysisBlockedByAllowance == true },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
                // Fetch a window rather than one row so a deferred recording the
                // user is already retrying by hand is stepped over instead of
                // ending the whole pass and stranding the backlog behind it.
                descriptor.fetchLimit = ProcessingPolicy.deferredResumeLimit
                let candidates = (try? modelContext.fetch(descriptor)) ?? []
                guard let candidateIndex = ProcessingPolicy.nextResumeIndex(
                    in: candidates.map(\.id),
                    skippingActive: self.activeRecordingIDs
                ) else { return }
                let next = candidates[candidateIndex]

                let id = next.id
                self.activeRecordingIDs.insert(id)
                let deferredJob = Task { [weak self] in
                    guard let self else { return }
                    await self.process(
                        recordingID: id,
                        modelContext: modelContext,
                        speechService: speechService,
                        llmService: llmService
                    )
                }
                self.activeTasks[id] = deferredJob
                await deferredJob.value
                self.activeTasks[id] = nil
                self.activeRecordingIDs.remove(id)

                // Re-fetch rather than reuse `next`: processing can take minutes
                // and the user may have deleted it meanwhile. A recording still
                // flagged deferred means the allowance ran out mid-run, so stop;
                // a deleted one just means move on.
                var check = FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })
                check.fetchLimit = 1
                let after = (try? modelContext.fetch(check))?.first
                if ProcessingPolicy.stopsResumePass(
                    doesRecordingExist: after != nil,
                    stillBlockedByAllowance: after?.analysisBlockedByAllowance == true
                ) {
                    return
                }
            }
        }
        resumeTask = pass
    }

    private func process(
        recordingID: UUID,
        modelContext: ModelContext,
        speechService: SpeechService,
        llmService: LLMService
    ) async {
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "SpeakUp.ProcessRecording"
        ) {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }

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
        let reservation = ProcessingPolicy.reservation(for: decision, reservedAnalyses: reservedAnalyses)
        guard !reservation.shouldDefer else {
            recording.isProcessing = false
            recording.lastProcessingError = nil
            recording.analysisBlockedByAllowance = true
            save(modelContext, context: "deferring analysis past free allowance \(recordingID.uuidString)")
            AnalyticsService.shared.log(.allowanceExhausted())
            return
        }
        if reservation.holdsReservation { reservedAnalyses += 1 }
        defer { if reservation.holdsReservation { reservedAnalyses -= 1 } }

        if recording.analysisBlockedByAllowance {
            recording.analysisBlockedByAllowance = false
        }

        recording.isProcessing = true
        recording.lastProcessingError = nil
        save(modelContext, context: "marking recording processing \(recordingID.uuidString)")

        let startedAt = Date()
        let vocabWorkout = VocabChallengeService.todaysChallenge(
            preferences: settings?.vocabChallengePreferences ?? .disabled
        )
        let vocabWords = VocabMatcher.mergeUnique(
            settings?.vocabWords ?? [],
            vocabWorkout?.words.map(\.text) ?? []
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

                if Task.isCancelled {
                    persisted.isProcessing = false
                    save(modelContext, context: "clearing processing flag after cancellation \(recordingID.uuidString)")
                    return
                }

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
            if Task.isCancelled {
                persisted.isProcessing = false
                save(modelContext, context: "clearing processing flag after cancellation \(recordingID.uuidString)")
                return
            }
            if let text = computed.2 {
                persisted.transcriptionText = text
            }
            persisted.transcriptionWords = computed.1
            persisted.setAnalysis(computed.0)
            // Speaking a tracked word is its review — grade it here so the
            // schedule stays right for users who never open the Today tab.
            VocabChallengeService.recordUsage(
                computed.0.vocabWordsUsed,
                preferences: settings?.vocabChallengePreferences ?? .disabled
            )
            // Snapshot the workout as it stood the moment analysis landed.
            // The detail view scores this recording against these words
            // forever, so an older take can never be judged by a later day's
            // list. Only a non-empty pick writes one; failure paths above
            // return before this, so no snapshot outlives a failed analysis.
            if let vocabWorkout, !vocabWorkout.words.isEmpty {
                persisted.vocabChallengeDayStamp = vocabWorkout.dayStamp
                persisted.vocabChallengeWords = vocabWorkout.words
            }
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
            // Widgets render from the App Group snapshot, not SwiftData, so a
            // bare reload just re-rendered stale numbers. Write the two values
            // an analysis actually changes, then drop the fingerprint — Today
            // owns the rest of the payload and rewrites it wholesale on the
            // next visit once the change gate reports a diff.
            WidgetDataProvider.updateLastScore(computed.0.speechScore.overall)
            WidgetDataProvider.updateLastPracticeDate(persisted.date)
            WidgetDataProvider.resetTodayFingerprint()
            WidgetCenter.shared.reloadAllTimelines()
        } catch is CancellationError {
            // Delete / dismiss cancelled the job — not a user-visible failure.
            guard let persisted = fetchRecording(with: descriptor, modelContext: modelContext) else { return }
            persisted.isProcessing = false
            // Leave any prior error alone; never stamp a cancellation string.
            save(modelContext, context: "clearing processing flag after cancellation \(recordingID.uuidString)")
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

    private static func failureCategory(for error: Error) -> String {
        if error is CancellationError { return "cancelled" }
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

        if !conversationDetected,
           transcription.duration >= 30,
           analysis.totalWords >= 40,
           (60...260).contains(analysis.wordsPerMinute) {
            let previous = settings.calibratedWPM ?? Double(settings.targetWPM)
            let blended = previous * (1 - alpha) + analysis.wordsPerMinute * alpha
            settings.calibratedWPM = min(max(blended, 110), 190)
        }
    }

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

        // Runs detached: the pipeline is pure statics (see
        // `SpeechAnalysisPipeline`), so scoring needs neither the
        // MainActor-isolated service instance nor the Whisper model.
        return await Task.detached(priority: .userInitiated) {
            () -> (analysis: SpeechAnalysis, markedWords: [TranscriptionWord]) in
            let levelSamples: [Float] = {
                if !audioLevelSamples.isEmpty { return audioLevelSamples }
                guard let audioURL,
                      FileManager.default.fileExists(atPath: audioURL.path) else { return [] }
                let binCount = max(20, min(Int(actualDuration * 2), 7200))
                let peaks = AudioWaveformGenerator.generatePeaks(from: audioURL, binCount: binCount)
                return peaks.map { 20 * log10(max($0, 1e-4)) }
            }()
            let analysis = SpeechAnalysisPipeline.analyze(
                transcription: resultSnapshot,
                actualDuration: actualDuration,
                vocabWords: vocabWords,
                audioLevelSamples: levelSamples,
                audioURL: audioURL,
                promptText: promptText,
                targetWPM: targetWPM,
                trackFillerWords: trackFillerWords,
                trackPauses: trackPauses,
                scoreWeights: scoreWeights,
                audioIsolationMetrics: resultSnapshot.audioIsolationMetrics,
                speakerIsolationMetrics: resultSnapshot.speakerIsolationMetrics,
                monoPCM: resultSnapshot.monoPCM
            )
            let markedWords = VocabMatcher.mark(resultSnapshot.words, vocabWords: vocabWords)
            return (analysis, markedWords)
        }.value
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

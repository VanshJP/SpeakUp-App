import Foundation
import SwiftData
import os

@MainActor
@Observable
final class RecordingProcessingCoordinator {
    static let shared = RecordingProcessingCoordinator()

    private let logger = Logger(subsystem: "com.vansh.SpeakUpMore", category: "RecordingProcessing")
    private var activeRecordingIDs: Set<UUID> = []

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

        guard let mediaURL = recording.resolvedAudioURL ?? recording.resolvedVideoURL,
              FileManager.default.fileExists(atPath: mediaURL.path) else {
            recording.isProcessing = false
            save(modelContext, context: "clearing processing flag for missing media \(recordingID.uuidString)")
            return
        }

        recording.isProcessing = true
        save(modelContext, context: "marking recording processing \(recordingID.uuidString)")

        let settings = fetchSettings(from: modelContext)
        let vocabWords = settings?.vocabWords ?? []
        let scoreWeights = scoreWeights(from: settings)

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
                    llmService.unloadLocalModel()
                }

                let transcription = try await withThrowingTaskGroup(of: SpeechTranscriptionResult.self) { group in
                    group.addTask {
                        try await speechService.transcribe(
                            audioURL: mediaURL,
                            fillerConfig: fillerConfig,
                            preferredTerms: preferredTerms,
                            voiceProfile: voiceProfile
                        )
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(90))
                        throw SpeechServiceError.transcriptionFailed(
                            NSError(
                                domain: "SpeakUp",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Transcription timed out"]
                            )
                        )
                    }
                    let first = try await group.next()!
                    group.cancelAll()
                    return first
                }

                let analyzed = await analyzeTranscript(
                    transcription: transcription,
                    recording: recording,
                    vocabWords: vocabWords,
                    scoreWeights: scoreWeights,
                    settings: settings,
                    promptText: effectivePromptText(for: recording, modelContext: modelContext)
                )
                computed = (
                    analyzed.analysis,
                    analyzed.markedWords,
                    transcription.text,
                    transcription.voiceProfileUpdate
                )

                if let update = computed.3, let settings {
                    let conversationDetected = transcription.speakerIsolationMetrics?.conversationDetected ?? false
                    if !conversationDetected || update.separationConfidence >= 50 {
                        let alpha = 0.3
                        if let existing = settings.voiceProfileF0Hz, settings.voiceProfileSampleCount > 0 {
                            settings.voiceProfileF0Hz = existing * (1 - alpha) + update.sessionF0Hz * alpha
                            settings.voiceProfileEnergyDb = (settings.voiceProfileEnergyDb ?? 0) * (1 - alpha) + update.sessionEnergyDb * alpha
                        } else {
                            settings.voiceProfileF0Hz = update.sessionF0Hz
                            settings.voiceProfileEnergyDb = update.sessionEnergyDb
                        }
                        settings.voiceProfileSampleCount += 1
                        settings.voiceProfileLastUpdated = Date()
                    }
                }
            }

            if let text = computed.2 {
                recording.transcriptionText = text
            }
            recording.transcriptionWords = computed.1
            recording.analysis = computed.0
            recording.isProcessing = false
            save(modelContext, context: "persisting analysis for \(recordingID.uuidString)")
        } catch {
            logger.error("Recording processing failed for \(recordingID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            recording.isProcessing = false
            save(modelContext, context: "clearing processing flag after error \(recordingID.uuidString)")
        }
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
        let targetWPM = settings?.targetWPM ?? 150
        let trackFillerWords = settings?.trackFillerWords ?? true
        let trackPauses = settings?.trackPauses ?? true

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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

    private func scoreWeights(from settings: UserSettings?) -> ScoreWeights {
        guard let settings else { return .defaults }
        return ScoreWeights(
            clarity: settings.clarityWeight,
            pace: settings.paceWeight,
            filler: settings.fillerWeight,
            pause: settings.pauseWeight,
            vocalVariety: settings.vocalVarietyWeight,
            delivery: settings.deliveryWeight,
            vocabulary: settings.vocabularyWeight,
            structure: settings.structureWeight,
            relevance: settings.relevanceWeight
        )
    }

    private func fetchRecording(
        with descriptor: FetchDescriptor<Recording>,
        modelContext: ModelContext
    ) -> Recording? {
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch recording for processing: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchSettings(from modelContext: ModelContext) -> UserSettings? {
        do {
            return try modelContext.fetch(FetchDescriptor<UserSettings>()).first
        } catch {
            logger.error("Failed to fetch user settings for processing: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    private func save(_ modelContext: ModelContext, context: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            logger.error("Failed to save model context (\(context, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

import Foundation
import SwiftData
import UIKit

extension RecordingViewModel {
    // MARK: - Recording Control

    func startRecording() async {
        do {
            recordingURL = try await audioService.startRecording()

            logPracticeStart()
            isRecording = true
            UIApplication.shared.isIdleTimerDisabled = true
            Haptics.medium()
            coachingService.reset()
            startTimer()
            startAudioLevelMonitoring()

            // Start live filler counting after the recorder owns the mic route.
            // Immediate dual-start (esp. "Start Now" mid-countdown) races the
            // session into a 0 Hz format and aborts inside AVAudioEngine.
            liveTranscriptionService.fillerConfig = fillerConfig
            let authorized = await liveTranscriptionService.requestAuthorization()
            if authorized {
                try? await Task.sleep(for: .milliseconds(150))
                guard isRecording else { return }
                liveTranscriptionService.start()
            }
        } catch {
            self.error = error
        }
    }

    func stopRecording() async -> Recording? {
        // Serializes the stop-button / timer-expiry / interruption races —
        // everything below up to the first await runs synchronously on MainActor.
        guard isRecording else { return nil }

        timer?.invalidate()
        timer = nil
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()
        coachingService.reset()

        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        isProcessing = true
        Haptics.success()

        defer { isProcessing = false }

        let finalURL = await audioService.stopRecording()
        let actualDuration = audioService.recordingDuration

        guard let url = finalURL, let context = modelContext else {
            if finalURL == nil {
                self.error = AudioServiceError.recordingFailed(
                    NSError(
                        domain: "SpeakUp",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Recording could not be saved."]
                    )
                )
            }
            return nil
        }

        let recording = Recording(
            prompt: prompt,
            targetDuration: targetDuration.seconds,
            actualDuration: actualDuration,
            mediaType: .audio,
            audioURL: url,
            isProcessing: true,
            audioLevelSamples: audioLevelSamples,
            goalId: goalId
        )

        recording.storyId = storyId

        // Denormalize story title for display in history
        if let storyId {
            let targetId = storyId
            var storyDescriptor = FetchDescriptor<Story>()
            storyDescriptor.predicate = #Predicate<Story> { $0.id == targetId }
            if let story = try? context.fetch(storyDescriptor).first {
                recording.storyTitle = story.title
            }
        }

        context.insert(recording)

        do {
            try context.save()

            // Update linked story practice stats
            if let storyId {
                let targetId = storyId
                var storyDescriptor = FetchDescriptor<Story>()
                storyDescriptor.predicate = #Predicate<Story> { $0.id == targetId }
                if let story = try? context.fetch(storyDescriptor).first {
                    story.practiceCount += 1
                    story.lastPracticeDate = Date()
                    story.updatedAt = Date()
                    // bestScore updates in RecordingProcessingCoordinator once
                    // analysis exists — it is always nil at this point.
                    try? context.save()
                }
            }

            return recording
        } catch {
            self.error = error
            return nil
        }
    }

    func cancelRecording() {
        timer?.invalidate()
        timer = nil
        stopAudioLevelMonitoring()
        liveTranscriptionService.stop()

        audioService.cancelRecording()

        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        recordingURL = nil
    }

    // MARK: - Analytics

    /// Reports the start of a session so the funnel can measure how many
    /// starts reach a score. Logged once the recorder is actually running, not
    /// when the screen opens — an abandoned countdown is not a practice start.
    private func logPracticeStart() {
        let useCase: String
        if sessionSource == SharedPromptLink.shareSource {
            useCase = "shared_prompt"
        } else if storyId != nil {
            useCase = "story"
        } else if prompt != nil {
            useCase = "prompt"
        } else if goalId != nil {
            useCase = "goal"
        } else {
            useCase = "free"
        }

        let sessionNumber = modelContext.map { context in
            (try? context.fetchCount(FetchDescriptor<Recording>())) ?? 0
        } ?? 0

        AnalyticsService.shared.log(
            .practiceStarted(useCase: useCase, sessionNumber: sessionNumber + 1)
        )
    }
}

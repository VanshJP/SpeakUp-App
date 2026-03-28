import Foundation
import SwiftData
import UIKit

extension RecordingViewModel {
    // MARK: - Recording Control

    @MainActor
    func startRecording() async {
        do {
            recordingURL = try await audioService.startRecording()

            isRecording = true
            UIApplication.shared.isIdleTimerDisabled = true
            Haptics.medium()
            coachingService.reset()
            startTimer()
            startAudioLevelMonitoring()

            // Start live filler counting (after recorder is active so session is ready)
            liveTranscriptionService.fillerConfig = fillerConfig
            let authorized = await liveTranscriptionService.requestAuthorization()
            if authorized {
                liveTranscriptionService.start()
            }
        } catch {
            self.error = error
        }
    }

    @MainActor
    func stopRecording() async -> Recording? {
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
            return nil
        }

        let recording = Recording(
            prompt: prompt,
            targetDuration: targetDuration.seconds,
            actualDuration: actualDuration,
            mediaType: .audio,
            audioURL: url,
            isProcessing: true,
            goalId: goalId
        )

        recording.eventId = eventId
        recording.scriptVersionId = scriptVersionId
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
                    if let score = recording.analysis?.speechScore.overall, score > story.bestScore {
                        story.bestScore = score
                    }
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
}

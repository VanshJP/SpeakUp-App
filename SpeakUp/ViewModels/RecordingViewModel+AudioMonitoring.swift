import Foundation

extension RecordingViewModel {
    // MARK: - Audio Level Monitoring

    func startAudioLevelMonitoring() {
        audioLevelSampleCounter = 0
        audioLevelSamples = []
        lastCoachingWordCount = 0
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let level = self.audioService.getAudioLevel()
                self.audioLevel = level

                // Collect sample every ~0.5s (every 10th tick at 0.05s interval)
                self.audioLevelSampleCounter += 1
                if self.audioLevelSampleCounter >= 5 {
                    self.audioLevelSampleCounter = 0
                    self.audioLevelSamples.append(level)

                    // Feed coaching service (every ~0.5s is enough)
                    self.coachingService.processAudioLevel(level)
                    self.coachingService.processFillerDetected(currentCount: self.liveFillerCount)

                    // Detect new words for pace tracking
                    let currentWords = self.liveTranscriptionService.liveWordCount
                    let newWords = currentWords - self.lastCoachingWordCount
                    for _ in 0..<newWords {
                        self.coachingService.processWordTimestamp()
                    }
                    self.lastCoachingWordCount = currentWords
                }
            }
        }
    }

    func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = -160
    }
}

import Foundation

extension RecordingViewModel {
    // MARK: - Audio Level Monitoring

    func startAudioLevelMonitoring() {
        audioLevelSampleCounter = 0
        audioLevelSamples = []
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let level = self.audioService.getAudioLevel()
                self.audioLevel = level

                // Collect sample every ~0.5s (every 10th tick at 0.05s interval)
                self.audioLevelSampleCounter += 1
                if self.audioLevelSampleCounter >= 10 {
                    self.audioLevelSampleCounter = 0
                    self.audioLevelSamples.append(level)
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

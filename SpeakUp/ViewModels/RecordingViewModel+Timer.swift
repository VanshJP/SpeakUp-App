import Foundation

extension RecordingViewModel {
    // MARK: - Timer

    func startTimer() {
        remainingTime = TimeInterval(targetDuration.seconds)
        progress = countdownStyle == .countDown ? 1.0 : 0.0

        // Brief pause so the user sees the full starting state
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }

                Task { @MainActor in
                    self.remainingTime -= 0.1
                    self.recordingDuration = TimeInterval(self.targetDuration.seconds) - self.remainingTime

                    // Haptic pulse at 10s and 5s remaining
                    if abs(self.remainingTime - 10.0) < 0.1 {
                        Haptics.warning()
                    } else if abs(self.remainingTime - 5.0) < 0.1 {
                        Haptics.heavy()
                    }

                    if self.remainingTime <= 0 {
                        // Clamp progress once timer expires
                        self.progress = self.countdownStyle == .countDown ? 0.0 : 1.0

                        if self.timerEndBehavior == .saveAndStop {
                            let timeSinceLastWord = self.recordingDuration - self.liveTranscriptionService.lastSegmentEndTime
                            let isQuiet = self.audioLevel < self.silenceDbThreshold

                            if !self.isWaitingForSentenceEnd {
                                // Timer just expired — check if user is mid-sentence
                                let isMidSentence = self.liveTranscriptionService.isActive
                                    && self.liveTranscriptionService.lastSegmentEndTime > 0
                                    && (timeSinceLastWord < self.sentenceSilenceThreshold || !isQuiet)

                                if isMidSentence {
                                    // User is still speaking — enter grace period
                                    self.isWaitingForSentenceEnd = true
                                    self.graceStartTime = self.recordingDuration
                                    Haptics.light()
                                } else {
                                    // Not mid-sentence — stop immediately
                                    self.timer?.invalidate()
                                    self.timer = nil
                                    self.autoSavedRecording = await self.stopRecording()
                                }
                            } else {
                                // Already in grace period — check for sentence end or timeout
                                let graceElapsed = self.recordingDuration - (self.graceStartTime ?? self.recordingDuration)

                                // Sentence ended = enough silence AND audio level is low
                                let sentenceEnded = timeSinceLastWord >= self.sentenceSilenceThreshold && isQuiet
                                let graceExpired = graceElapsed >= self.maxGracePeriod

                                if sentenceEnded || graceExpired {
                                    self.isWaitingForSentenceEnd = false
                                    self.graceStartTime = nil
                                    self.timer?.invalidate()
                                    self.timer = nil
                                    self.autoSavedRecording = await self.stopRecording()
                                }
                            }
                        }
                        // .keepGoing: timer continues into negative, recording keeps going
                    } else {
                        let rawProgress = 1 - (self.remainingTime / TimeInterval(self.targetDuration.seconds))
                        self.progress = self.countdownStyle == .countDown ? (1 - rawProgress) : rawProgress
                    }
                }
            }
        }
    }
}

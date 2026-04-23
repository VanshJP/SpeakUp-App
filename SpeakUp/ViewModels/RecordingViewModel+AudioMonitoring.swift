import Foundation

extension RecordingViewModel {
    // MARK: - Audio Level Monitoring
    //
    // The actual 10 Hz tick is driven by `timer` in RecordingViewModel+Timer;
    // that loop calls `sampleAudioLevelTick()` once per tick so we do not
    // run two timers in parallel. These helpers manage only state lifecycle.

    func startAudioLevelMonitoring() {
        audioLevelSampleCounter = 0
        audioLevelSamples = []
        // Reserve an upper bound ahead of time so routine appends don't
        // cause mid-recording allocations. 2 samples/sec + a small cushion.
        audioLevelSamples.reserveCapacity(targetDuration.seconds * 2 + 32)
        lastCoachingWordCount = 0
    }

    func stopAudioLevelMonitoring() {
        audioLevel = -160
    }

    /// Called once per 10 Hz timer tick from `startTimer()`. Reads the
    /// current level, writes it to `audioLevel` only when it changes by at
    /// least 1 dB (perf-patterns §1 — avoid redundant `@Observable` writes),
    /// and samples into `audioLevelSamples` / coaching services every 5th
    /// tick (~0.5 s).
    func sampleAudioLevelTick() {
        let level = audioService.getAudioLevel()
        if abs(level - audioLevel) >= 1.0 {
            audioLevel = level
        }

        audioLevelSampleCounter += 1
        guard audioLevelSampleCounter >= 5 else { return }
        audioLevelSampleCounter = 0

        // Soft cap with FIFO drop for long `.keepGoing` sessions.
        if audioLevelSamples.count >= RecordingViewModel.audioLevelSampleCap {
            audioLevelSamples.removeFirst(RecordingViewModel.audioLevelSampleDropChunk)
        }
        audioLevelSamples.append(level)

        coachingService.processAudioLevel(level)
        coachingService.processFillerDetected(currentCount: liveFillerCount)

        let currentWords = liveTranscriptionService.liveWordCount
        let newWords = currentWords - lastCoachingWordCount
        if newWords > 0 {
            for _ in 0..<newWords {
                coachingService.processWordTimestamp()
            }
            lastCoachingWordCount = currentWords
        }
    }
}

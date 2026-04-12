import Foundation

@Observable
@MainActor
final class RecordingDetailPlaybackViewModel {
    var isPlaying = false
    var playbackProgress: Double = 0
    var currentTime: TimeInterval = 0
    var playbackDuration: TimeInterval = 0
    var transcriptDuration: TimeInterval = 0

    func configureTranscript(words: [TranscriptionWord]) {
        transcriptDuration = words
            .map(\.end)
            .max() ?? 0
    }

    func sync(from audioService: AudioService, fallbackDuration: TimeInterval) {
        isPlaying = audioService.isPlaying

        let resolvedDuration = audioService.playbackDuration > 0
            ? audioService.playbackDuration
            : fallbackDuration
        playbackDuration = max(0, resolvedDuration)

        let normalizedProgress = max(0, min(1, audioService.playbackProgress))
        playbackProgress = normalizedProgress
        currentTime = normalizedProgress * max(playbackDuration, 0)
    }

    var syncedTranscriptTime: TimeInterval {
        guard currentTime > 0 else { return 0 }
        guard playbackDuration > 0, transcriptDuration > 0 else { return currentTime }

        // Align word timestamps to playback when Whisper timing and media duration drift.
        let scale = transcriptDuration / playbackDuration
        guard abs(scale - 1.0) > 0.015 else { return currentTime }
        return currentTime * scale
    }
}

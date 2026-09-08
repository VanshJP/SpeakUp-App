import Foundation

@Observable
@MainActor
final class RecordingDetailPlaybackViewModel {
    var isPlaying = false
    var playbackProgress: Double = 0
    var currentTime: TimeInterval = 0
    var playbackDuration: TimeInterval = 0

    func sync(from audioService: AudioService, fallbackDuration: TimeInterval) {
        isPlaying = audioService.isPlaying

        let resolvedDuration = audioService.playbackDuration > 0
            ? audioService.playbackDuration
            : fallbackDuration
        playbackDuration = max(0, resolvedDuration)

        // Authoritative time comes directly from AVAudioPlayer via AudioService.
        let clampedTime = max(0, min(audioService.currentPlaybackTime, playbackDuration))
        currentTime = clampedTime

        // Derive progress from time so scrubber and highlight stay in lockstep.
        if playbackDuration > 0 {
            playbackProgress = max(0, min(1, clampedTime / playbackDuration))
        } else {
            playbackProgress = max(0, min(1, audioService.playbackProgress))
        }
    }
}

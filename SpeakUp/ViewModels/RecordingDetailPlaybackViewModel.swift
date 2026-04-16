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

        let normalizedProgress = max(0, min(1, audioService.playbackProgress))
        playbackProgress = normalizedProgress
        currentTime = normalizedProgress * max(playbackDuration, 0)
    }
}

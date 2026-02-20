import AVFoundation
import CoreGraphics

enum AudioWaveformGenerator {
    /// Read an audio file and produce `binCount` peak level values normalized to a given height range.
    static func generate(from url: URL, binCount: Int, minHeight: CGFloat = 12, maxHeight: CGFloat = 36) -> [CGFloat] {
        guard binCount > 0,
              let audioFile = try? AVAudioFile(forReading: url) else {
            return fallbackHeights(count: binCount, minHeight: minHeight, maxHeight: maxHeight)
        }

        let format = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)
        guard totalFrames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return fallbackHeights(count: binCount, minHeight: minHeight, maxHeight: maxHeight)
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return fallbackHeights(count: binCount, minHeight: minHeight, maxHeight: maxHeight)
        }

        guard let channelData = buffer.floatChannelData?[0] else {
            return fallbackHeights(count: binCount, minHeight: minHeight, maxHeight: maxHeight)
        }

        let frameCount = Int(buffer.frameLength)
        let framesPerBin = max(1, frameCount / binCount)

        var peaks: [Float] = []
        for bin in 0..<binCount {
            let start = bin * framesPerBin
            let end = min(start + framesPerBin, frameCount)
            var peak: Float = 0
            for i in start..<end {
                let sample = abs(channelData[i])
                if sample > peak { peak = sample }
            }
            peaks.append(peak)
        }

        // Normalize peaks to height range
        let maxPeak = peaks.max() ?? 1
        let normalizer: Float = maxPeak > 0 ? maxPeak : 1

        return peaks.map { peak in
            let normalized = CGFloat(peak / normalizer)
            return minHeight + normalized * (maxHeight - minHeight)
        }
    }

    private static func fallbackHeights(count: Int, minHeight: CGFloat, maxHeight: CGFloat) -> [CGFloat] {
        let mid = (minHeight + maxHeight) / 2
        return Array(repeating: mid, count: max(count, 1))
    }
}

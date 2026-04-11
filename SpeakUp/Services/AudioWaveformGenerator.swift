import AVFoundation
import CoreGraphics

enum AudioWaveformGenerator {
    /// Normalize raw peaks (0...1) into UI bar heights for the detail drawer.
    static func heights(
        from peaks: [Float],
        minHeight: CGFloat = 12,
        maxHeight: CGFloat = 36
    ) -> [CGFloat] {
        guard !peaks.isEmpty else {
            return fallbackHeights(count: 50, minHeight: minHeight, maxHeight: maxHeight)
        }
        let normalizer: Float = (peaks.max() ?? 1) > 0 ? (peaks.max() ?? 1) : 1
        return peaks.map { peak in
            let normalized = CGFloat(peak / normalizer)
            return minHeight + normalized * (maxHeight - minHeight)
        }
    }

    /// Read an audio file in small chunks and produce `binCount` peak values.
    /// Uses a fixed-size buffer instead of allocating the full PCM buffer up front
    /// so memory stays bounded regardless of recording length.
    static func generatePeaks(from url: URL, binCount: Int) -> [Float] {
        guard binCount > 0,
              let audioFile = try? AVAudioFile(forReading: url) else {
            return []
        }

        let format = audioFile.processingFormat
        let totalFrames = Int(audioFile.length)
        guard totalFrames > 0 else { return [] }

        let framesPerBin = max(1, totalFrames / binCount)
        let chunkSize: AVAudioFrameCount = 32_768

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            return []
        }

        var peaks = [Float](repeating: 0, count: binCount)
        var framesRead = 0

        while framesRead < totalFrames {
            buffer.frameLength = 0
            do {
                try audioFile.read(into: buffer)
            } catch {
                break
            }

            let readFrames = Int(buffer.frameLength)
            if readFrames == 0 { break }

            guard let channelData = buffer.floatChannelData?[0] else { break }

            for i in 0..<readFrames {
                let globalFrame = framesRead + i
                let bin = min(binCount - 1, globalFrame / framesPerBin)
                let sample = abs(channelData[i])
                if sample > peaks[bin] {
                    peaks[bin] = sample
                }
            }

            framesRead += readFrames
        }

        return peaks
    }

    /// Legacy entry point retained for callers that want heights directly.
    static func generate(
        from url: URL,
        binCount: Int,
        minHeight: CGFloat = 12,
        maxHeight: CGFloat = 36
    ) -> [CGFloat] {
        let peaks = generatePeaks(from: url, binCount: binCount)
        if peaks.isEmpty {
            return fallbackHeights(count: binCount, minHeight: minHeight, maxHeight: maxHeight)
        }
        return heights(from: peaks, minHeight: minHeight, maxHeight: maxHeight)
    }

    private static func fallbackHeights(count: Int, minHeight: CGFloat, maxHeight: CGFloat) -> [CGFloat] {
        let mid = (minHeight + maxHeight) / 2
        return Array(repeating: mid, count: max(count, 1))
    }
}

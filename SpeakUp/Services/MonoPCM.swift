import Foundation
@preconcurrency import AVFoundation
import os

/// Mono float32 PCM decoded once per take and shared by every acoustic
/// analysis consumer (isolation preprocess, speaker labeling, pitch).
/// Previously each service re-decoded the whole file, materializing the
/// full sample array up to three times per analysis.
nonisolated struct MonoPCM: Sendable {
    let samples: [Float]
    let sampleRate: Double

    // MARK: - Decoding

    /// Decode any AVAudio-readable file to mono float32 at the file's sample rate.
    static func decode(url: URL) -> MonoPCM? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sourceFormat = file.processingFormat
        let sampleRate = sourceFormat.sampleRate
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return nil }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount) else {
            return nil
        }

        if sourceFormat.channelCount == 1 && sourceFormat.commonFormat == .pcmFormatFloat32 {
            do {
                try file.read(into: monoBuffer)
            } catch {
                return nil
            }
        } else {
            // Convert inside a scope so the source-format buffer is released
            // before the sample array is copied out.
            let converted: Bool = {
                guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
                    return false
                }
                do {
                    try file.read(into: sourceBuffer)
                } catch {
                    return false
                }
                guard let converter = AVAudioConverter(from: sourceFormat, to: monoFormat) else { return false }
                let status = converter.convert(to: monoBuffer, error: nil) { _, outStatus in
                    outStatus.pointee = .haveData
                    return sourceBuffer
                }
                return status != .error
            }()
            guard converted else { return nil }
        }

        guard let channelData = monoBuffer.floatChannelData else { return nil }
        let sampleCount = Int(monoBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: sampleCount))
        return MonoPCM(samples: samples, sampleRate: sampleRate)
    }
}

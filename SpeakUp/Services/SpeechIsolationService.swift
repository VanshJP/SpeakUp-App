import Foundation
import AVFoundation

/// Speech-focused audio enhancement prior to ASR.
/// Applies a light high-pass filter and adaptive noise gate to reduce
/// stationary background noise while preserving near-field speech.
enum SpeechIsolationService {
    struct Result {
        let processedAudioURL: URL
        let metrics: AudioIsolationMetrics
    }

    static func preprocessIfBeneficial(audioURL: URL) -> Result? {
        guard let mono = loadMonoPCM(url: audioURL) else { return nil }
        guard mono.samples.count > Int(mono.sampleRate * 1.5) else { return nil }

        let baselineSNR = estimateSNR(samples: mono.samples, sampleRate: mono.sampleRate)

        // Skip processing if audio already has excellent signal quality.
        // Lowered threshold from 18 dB to 22 dB:
        // - 18 dB was too conservative: recordings with 15-18 dB SNR benefit from processing
        //   but were being skipped, leaving noisy audio going into Whisper.
        // - 22 dB is a more realistic "already clean enough" threshold for mobile recordings.
        //   Studio-quality speech is typically 30+ dB; 22 dB still has audible background noise.
        // - This means more recordings get processed, improving Whisper accuracy and
        //   downstream speaker isolation quality.
        guard baselineSNR < 22.0 else { return nil }

        let highPassed = applyHighPassFilter(to: mono.samples)
        let gated = applyAdaptiveNoiseGate(to: highPassed, sampleRate: mono.sampleRate)
        let improvedSNR = estimateSNR(samples: gated, sampleRate: mono.sampleRate)
        let delta = improvedSNR - baselineSNR

        // Skip writing an alternate file when enhancement does not improve signal quality.
        guard delta > 0.3 else { return nil }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("speakup_isolated_\(UUID().uuidString).caf")

        guard writeMonoPCM(samples: gated, sampleRate: mono.sampleRate, to: outputURL) else {
            return nil
        }

        // Adjusted suppression score formula to account for the new 22 dB skip threshold.
        // Previously: (delta + 2.0) / 8.0 — a 6 dB improvement scored 100.
        // Now: (delta + 1.5) / 10.0 — a 8.5 dB improvement scores 100.
        // This gives a more honest score since we're now processing noisier audio.
        let suppressionScore = max(0, min(100, Int(((delta + 1.5) / 10.0) * 100.0)))
        // Adjusted residual noise score to match the new skip threshold.
        // Previously: (improvedSNR + 5.0) / 20.0 — 15 dB output SNR scored 100.
        // Now: (improvedSNR + 5.0) / 27.0 — 22 dB output SNR scores 100.
        // This prevents inflated residualNoiseScore values from over-dampening reliability.
        let residualNoiseScore = max(0, min(100, Int(((improvedSNR + 5.0) / 27.0) * 100.0)))

        return Result(
            processedAudioURL: outputURL,
            metrics: AudioIsolationMetrics(
                estimatedInputSNRDb: baselineSNR,
                estimatedOutputSNRDb: improvedSNR,
                suppressionDeltaDb: delta,
                suppressionScore: suppressionScore,
                residualNoiseScore: residualNoiseScore
            )
        )
    }

    // MARK: - Processing

    private static func applyHighPassFilter(to samples: [Float], alpha: Float = 0.97) -> [Float] {
        // Lowered alpha from 0.995 to 0.97.
        // alpha = 0.995 corresponds to a cutoff of ~(1-0.995)*sampleRate/(2π) ≈ 50 Hz at 44.1 kHz.
        // This was barely filtering anything — 50 Hz is below the fundamental of any human voice.
        // alpha = 0.97 corresponds to ~210 Hz cutoff, which:
        //   - Removes low-frequency rumble, HVAC hum, and handling noise (all below 200 Hz)
        //   - Preserves all speech fundamentals (male: 85-180 Hz, female: 165-255 Hz)
        //   - Improves SNR for the noise gate stage that follows
        // Note: This is a first-order IIR high-pass. The -3dB point is approximate.
        guard !samples.isEmpty else { return samples }
        var output = [Float](repeating: 0, count: samples.count)
        var previousInput: Float = samples[0]
        var previousOutput: Float = 0

        for i in samples.indices {
            let x = samples[i]
            let y = x - previousInput + alpha * previousOutput
            output[i] = y
            previousInput = x
            previousOutput = y
        }
        return output
    }

    private static func applyAdaptiveNoiseGate(to samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let frameSize = max(128, Int(sampleRate * 0.02))
        let frameRMS = rmsPerFrame(samples: samples, frameSize: frameSize)
        guard !frameRMS.isEmpty else { return samples }

        // Raised noise floor percentile from 20th to 15th percentile.
        // The 20th percentile includes some low-energy speech frames (soft consonants, pauses).
        // The 15th percentile more accurately captures the true noise floor.
        let noiseFloor = percentile(frameRMS, p: 0.15)
        // Raised threshold multiplier from 1.8x to 2.2x noise floor.
        // 1.8x was too close to the noise floor, causing the gate to partially suppress
        // quiet speech segments. 2.2x provides a cleaner separation between noise and speech.
        let threshold = max(noiseFloor * 2.2, 0.00012)

        var output = samples
        var smoothedGain: Float = 1.0
        let attack: Float = 0.35
        let release: Float = 0.10

        var frameIndex = 0
        var cursor = 0
        while cursor < output.count {
            let end = min(output.count, cursor + frameSize)
            let rms = frameRMS[min(frameIndex, frameRMS.count - 1)]
            let targetGain: Float

            if rms <= threshold * 0.6 {
                targetGain = 0.18
            } else if rms >= threshold * 2.0 {
                targetGain = 1.0
            } else {
                let normalized = (rms - threshold * 0.6) / (threshold * 1.4)
                targetGain = 0.18 + normalized * 0.82
            }

            if targetGain > smoothedGain {
                smoothedGain += (targetGain - smoothedGain) * attack
            } else {
                smoothedGain += (targetGain - smoothedGain) * release
            }

            for i in cursor..<end {
                output[i] = max(-1.0, min(1.0, output[i] * smoothedGain))
            }

            cursor += frameSize
            frameIndex += 1
        }

        return output
    }

    // MARK: - Signal Metrics

    private static func estimateSNR(samples: [Float], sampleRate: Double) -> Double {
        let frameSize = max(128, Int(sampleRate * 0.02))
        let rms = rmsPerFrame(samples: samples, frameSize: frameSize)
        guard !rms.isEmpty else { return 0 }

        let noise = max(1e-6, Double(percentile(rms, p: 0.20)))
        let speech = max(1e-6, Double(percentile(rms, p: 0.80)))
        return 20.0 * log10(speech / noise)
    }

    private static func rmsPerFrame(samples: [Float], frameSize: Int) -> [Float] {
        guard frameSize > 0, !samples.isEmpty else { return [] }
        var result: [Float] = []
        result.reserveCapacity(max(1, samples.count / frameSize))

        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + frameSize)
            let frame = samples[index..<end]
            let energy = frame.reduce(Float(0)) { partial, value in
                partial + (value * value)
            } / Float(max(1, frame.count))
            result.append(sqrt(max(1e-9, energy)))
            index += frameSize
        }

        return result
    }

    private static func percentile(_ values: [Float], p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let clampedP = min(max(0, p), 1)
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * clampedP).rounded())
        return sorted[max(0, min(sorted.count - 1, index))]
    }

    // MARK: - Audio I/O

    private struct MonoPCM {
        let samples: [Float]
        let sampleRate: Double
    }

    private static func loadMonoPCM(url: URL) -> MonoPCM? {
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

        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount) else {
            return nil
        }

        if sourceFormat.channelCount == 1 && sourceFormat.commonFormat == .pcmFormatFloat32 {
            do {
                try file.read(into: targetBuffer)
            } catch {
                return nil
            }
        } else {
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
                return nil
            }
            do {
                try file.read(into: sourceBuffer)
            } catch {
                return nil
            }
            guard let converter = AVAudioConverter(from: sourceFormat, to: monoFormat) else { return nil }
            let status = converter.convert(to: targetBuffer, error: nil) { _, outStatus in
                outStatus.pointee = .haveData
                return sourceBuffer
            }
            guard status != .error else { return nil }
        }

        guard let channelData = targetBuffer.floatChannelData else { return nil }
        let sampleCount = Int(targetBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: sampleCount))
        return MonoPCM(samples: samples, sampleRate: sampleRate)
    }

    private static func writeMonoPCM(samples: [Float], sampleRate: Double, to outputURL: URL) -> Bool {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return false }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData else { return false }
        for i in 0..<samples.count {
            channelData[0][i] = samples[i]
        }

        do {
            let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }
}

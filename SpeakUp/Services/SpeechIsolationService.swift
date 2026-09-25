import Foundation

/// Measures how much stationary background noise a take carries, for the
/// scoring pipeline's reliability stabilization (`residualNoiseScore`).
///
/// It used to also write a high-passed, noise-gated copy of the take for
/// Whisper to read. `SpeechTranscriber` handles room noise itself and a gate
/// can only take speech away from it, so the transcriber reads the original
/// file and only the measurement is left. The numbers are unchanged: they
/// still describe the take as the gate would have left it.
/// Pure DSP - must stay `nonisolated` under MainActor default isolation.
nonisolated enum SpeechIsolationService {
    /// Nil when the take is short or already clean (SNR 22 dB or better), or
    /// when a gate would not have helped - the same takes the old preprocess
    /// skipped, so scoring sees the same inputs.
    static func metrics(for monoPCM: MonoPCM) -> AudioIsolationMetrics? {
        guard monoPCM.samples.count > Int(monoPCM.sampleRate * 1.5) else { return nil }

        let baselineSNR = estimateSNR(samples: monoPCM.samples, sampleRate: monoPCM.sampleRate)
        // 22 dB is a realistic "already clean enough" bar for phone takes;
        // studio speech is typically 30+ dB.
        guard baselineSNR < 22.0 else { return nil }

        let highPassed = applyHighPassFilter(to: monoPCM.samples)
        let gated = applyAdaptiveNoiseGate(to: highPassed, sampleRate: monoPCM.sampleRate)
        let improvedSNR = estimateSNR(samples: gated, sampleRate: monoPCM.sampleRate)
        let delta = improvedSNR - baselineSNR
        guard delta > 0.3 else { return nil }

        // (delta + 1.5) / 10: an 8.5 dB improvement scores 100.
        let suppressionScore = max(0, min(100, Int(((delta + 1.5) / 10.0) * 100.0)))
        // (SNR + 5) / 27: 22 dB output SNR scores 100, matching the skip bar,
        // so residual noise never over-dampens reliability.
        let residualNoiseScore = max(0, min(100, Int(((improvedSNR + 5.0) / 27.0) * 100.0)))

        return AudioIsolationMetrics(
            estimatedInputSNRDb: baselineSNR,
            estimatedOutputSNRDb: improvedSNR,
            suppressionDeltaDb: delta,
            suppressionScore: suppressionScore,
            residualNoiseScore: residualNoiseScore
        )
    }

    // MARK: - Processing

    private static func applyHighPassFilter(to samples: [Float], alpha: Float = 0.99) -> [Float] {
        // alpha = 0.99 → cutoff ~(1-0.99)*sampleRate/(2π) ≈ 70 Hz at 44.1 kHz.
        // The previous 0.97 (~210 Hz) sat inside the male fundamental band (85-180 Hz)
        // and, combined with the adaptive noise gate, could suppress near-field speech
        // enough that Whisper returned an empty transcript ("Silent").
        // 70 Hz still strips rumble / HVAC while leaving speech fundamentals intact.
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
        // 2.0× noise floor - enough to separate stationary noise without
        // gating soft consonants / quiet near-field speech into the floor.
        let threshold = max(noiseFloor * 2.0, 0.00012)

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

            // Floor gain at 0.35 (was 0.18) so gated frames stay audible to ASR.
            if rms <= threshold * 0.6 {
                targetGain = 0.35
            } else if rms >= threshold * 2.0 {
                targetGain = 1.0
            } else {
                let normalized = (rms - threshold * 0.6) / (threshold * 1.4)
                targetGain = 0.35 + normalized * 0.65
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
}

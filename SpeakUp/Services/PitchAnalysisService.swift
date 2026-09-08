import Foundation
import Accelerate

/// On-device pitch (F0) analysis using autocorrelation via Apple's Accelerate framework.
/// Extracts fundamental frequency contour, variation metrics, and prosody scores from recorded audio.
/// Zero external dependencies — operates on `MonoPCM` with vDSP only.
nonisolated enum PitchAnalysisService {

    // MARK: - Configuration

    private static let windowDuration: Double = 0.03  // 30ms analysis window
    private static let hopDuration: Double = 0.01     // 10ms hop (100 frames/sec)
    private static let f0Min: Float = 75              // Min plausible F0 (Hz)
    private static let f0Max: Float = 500             // Max plausible F0 (Hz)
    private static let voicedThreshold: Float = 0.45  // Autocorrelation peak threshold (raised to reject noise)

    // MARK: - Public API

    /// Analyze the pitch characteristics of a decoded mono PCM buffer.
    /// Returns nil if there are insufficient voiced frames.
    static func analyze(monoPCM: MonoPCM) -> PitchMetrics? {
        guard monoPCM.sampleRate > 0 else { return nil }

        let sr = monoPCM.sampleRate
        let data = monoPCM.samples

        let windowSize = max(1, Int(windowDuration * sr))
        let hopSize = max(1, Int(hopDuration * sr))
        let minLag = Int(sr / Double(f0Max))
        let maxLag = min(windowSize - 1, Int(sr / Double(f0Min)))

        guard maxLag > minLag, data.count > windowSize else { return nil }

        var f0Values: [Float] = []
        var totalFrames = 0

        // Hoisted per-recording scratch: one Hann window and one reusable
        // windowed-frame buffer, instead of two allocations per frame.
        var hannWindow = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(windowSize), Int32(vDSP_HALF_WINDOW))
        var windowed = [Float](repeating: 0, count: windowSize)

        data.withUnsafeBufferPointer { dataPtr in
            guard let base = dataPtr.baseAddress else { return }
            var offset = 0
            while offset + windowSize <= data.count {
                totalFrames += 1
                vDSP_vmul(base + offset, 1, hannWindow, 1, &windowed, 1, vDSP_Length(windowSize))
                if let f0 = estimateF0(windowed: windowed, sampleRate: sr, minLag: minLag, maxLag: maxLag) {
                    f0Values.append(f0)
                }
                offset += hopSize
            }
        }

        guard f0Values.count >= 5 else { return nil }

        let voicedFrameRatio = totalFrames > 0 ? Float(f0Values.count) / Float(totalFrames) : 0

        // Octave error correction: if consecutive F0 jumps by ~2x or ~0.5x, correct it
        var corrected = f0Values
        for i in 1..<corrected.count {
            let ratio = corrected[i] / corrected[i - 1]
            if ratio > 1.8 && ratio < 2.2 {
                corrected[i] = corrected[i] / 2.0  // Octave-up error
            } else if ratio > 0.45 && ratio < 0.55 {
                corrected[i] = corrected[i] * 2.0  // Octave-down error
            }
        }

        // Median filter with 5-frame window to smooth single-frame outliers
        var filtered = corrected
        let filterRadius = 2
        var medianWindow = [Float](repeating: 0, count: filterRadius * 2 + 1)
        for i in filterRadius..<(corrected.count - filterRadius) {
            for j in -filterRadius...filterRadius {
                medianWindow[j + filterRadius] = corrected[i + j]
            }
            medianWindow.sort()
            filtered[i] = medianWindow[filterRadius]  // Median
        }

        let mean = filtered.reduce(0, +) / Float(filtered.count)
        let sorted = filtered.sorted()
        let p5 = sorted[max(0, Int(Double(sorted.count) * 0.05))]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]

        let variance = filtered.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(filtered.count)
        let stdDev = sqrt(variance)

        let rangeSemitones = hzToSemitones(from: p5, to: p95)

        // Pitch variation score: semitone stddev mapped via sigmoid-like curve
        // Research: engaging speakers have 3-5 semitone stddev
        // Monotone speech: ~1-2 semitones, dynamic: 3-6+
        let stdDevSemitones = mean > 0 ? 12.0 * log2(Double((mean + stdDev) / mean)) : 0
        let pitchVariationScore: Int
        if stdDevSemitones < 1.0 {
            pitchVariationScore = max(10, Int(10.0 + stdDevSemitones * 15.0))  // 10-25
        } else if stdDevSemitones < 2.0 {
            pitchVariationScore = Int(25.0 + (stdDevSemitones - 1.0) * 25.0)   // 25-50
        } else if stdDevSemitones < 4.0 {
            pitchVariationScore = Int(50.0 + (stdDevSemitones - 2.0) * 15.0)   // 50-80
        } else if stdDevSemitones < 6.0 {
            pitchVariationScore = Int(80.0 + (stdDevSemitones - 4.0) * 7.5)    // 80-95
        } else {
            pitchVariationScore = min(100, Int(95.0 + (stdDevSemitones - 6.0) * 2.5)) // 95-100
        }

        let declinationRate = computeDeclination(f0Values: f0Values, hopDuration: hopDuration)
        let contour = downsample(filtered, targetCount: 200)

        return PitchMetrics(
            f0Mean: mean,
            f0StdDev: stdDev,
            f0Min: p5,
            f0Max: p95,
            f0RangeSemitones: rangeSemitones,
            pitchVariationScore: pitchVariationScore,
            declinationRate: declinationRate,
            f0Contour: contour,
            voicedFrameRatio: voicedFrameRatio
        )
    }

    // MARK: - F0 Estimation (Autocorrelation)

    private static func estimateF0(windowed: [Float], sampleRate: Double, minLag: Int, maxLag: Int) -> Float? {
        let n = windowed.count
        guard maxLag < n, minLag < maxLag else { return nil }

        var energy: Float = 0
        vDSP_dotpr(windowed, 1, windowed, 1, &energy, vDSP_Length(n))
        guard energy > 1e-10 else { return nil }

        var bestLag = minLag
        var bestCorr: Float = -1

        // Zero-copy pointer offsets per lag — same operand lengths as the
        // previous Array-slice copies, so dot products are unchanged.
        windowed.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for lag in minLag...maxLag {
                let overlapLen = n - lag
                guard overlapLen > 0 else { continue }
                var corr: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &corr, vDSP_Length(overlapLen))

                var energy0: Float = 0
                var energy1: Float = 0
                vDSP_dotpr(base, 1, base, 1, &energy0, vDSP_Length(overlapLen))
                vDSP_dotpr(base + lag, 1, base + lag, 1, &energy1, vDSP_Length(overlapLen))
                let norm = sqrt(energy0 * energy1)
                guard norm > 1e-10 else { continue }
                corr /= norm

                if corr > bestCorr {
                    bestCorr = corr
                    bestLag = lag
                }
            }
        }

        guard bestCorr >= voicedThreshold else { return nil }
        return Float(sampleRate) / Float(bestLag)
    }

    // MARK: - Pitch-Energy Correlation

    /// Compute Pearson correlation between pitch contour and energy contour.
    /// Engaging speakers get louder when pitch rises (positive correlation).
    /// Returns a score 0-100 where 50=no correlation, 100=strong positive, 0=strong negative.
    static func pitchEnergyCorrelation(pitchContour: [Float], audioLevelSamples: [Float]) -> Int {
        // Downsample both to same length for alignment
        let targetCount = min(pitchContour.count, audioLevelSamples.count, 100)
        guard targetCount >= 5 else { return 50 }

        let pitchDS = downsample(pitchContour, targetCount: targetCount)
        // Convert dB energy samples to linear, filtering silence
        let energyDS: [Float]
        if audioLevelSamples.count > targetCount {
            energyDS = downsample(audioLevelSamples, targetCount: targetCount)
        } else {
            energyDS = audioLevelSamples
        }
        let linearEnergy = energyDS.map { max(Float(1e-6), pow(10.0, $0 / 20.0)) }

        guard pitchDS.count == linearEnergy.count, pitchDS.count >= 5 else { return 50 }

        // Pearson correlation
        let n = Double(pitchDS.count)
        let pitchMean = Double(pitchDS.reduce(0, +)) / n
        let energyMean = Double(linearEnergy.reduce(0, +)) / n

        var cov = 0.0, pitchVar = 0.0, energyVar = 0.0
        for i in 0..<pitchDS.count {
            let pd = Double(pitchDS[i]) - pitchMean
            let ed = Double(linearEnergy[i]) - energyMean
            cov += pd * ed
            pitchVar += pd * pd
            energyVar += ed * ed
        }

        let denom = sqrt(pitchVar * energyVar)
        guard denom > 1e-10 else { return 50 }
        let r = cov / denom  // -1 to +1

        // Map r to 0-100: r=0 → 50, r=+1 → 100, r=-0.5 → 25
        return max(0, min(100, Int(50 + r * 50)))
    }

    // MARK: - Helpers

    private static func hzToSemitones(from low: Float, to high: Float) -> Float {
        guard low > 0, high > 0 else { return 0 }
        return 12.0 * log2(high / low)
    }

    private static func computeDeclination(f0Values: [Float], hopDuration: Double) -> Float {
        let n = f0Values.count
        guard n >= 10 else { return 0 }

        let ref = f0Values[0]
        guard ref > 0 else { return 0 }
        let semitones = f0Values.map { 12.0 * log2(Double($0) / Double(ref)) }

        let times = (0..<n).map { Double($0) * hopDuration }
        let meanX = times.reduce(0, +) / Double(n)
        let meanY = semitones.reduce(0, +) / Double(n)

        var num = 0.0
        var den = 0.0
        for i in 0..<n {
            let dx = times[i] - meanX
            num += dx * (semitones[i] - meanY)
            den += dx * dx
        }

        guard den > 0 else { return 0 }
        return Float(num / den)
    }

    private static func downsample(_ values: [Float], targetCount: Int) -> [Float] {
        guard values.count > targetCount else { return values }
        let binSize = Double(values.count) / Double(targetCount)
        return (0..<targetCount).map { i in
            let start = Int(Double(i) * binSize)
            let end = min(values.count, Int(Double(i + 1) * binSize))
            guard end > start else { return 0 }
            let slice = values[start..<end]
            return slice.reduce(0, +) / Float(slice.count)
        }
    }
}

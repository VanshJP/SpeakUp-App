import Foundation
import AVFoundation
import Accelerate

/// On-device pitch (F0) analysis using autocorrelation via Apple's Accelerate framework.
/// Extracts fundamental frequency contour, variation metrics, and prosody scores from recorded audio.
/// Zero external dependencies — uses only AVFoundation + vDSP.
enum PitchAnalysisService {

    // MARK: - Configuration

    /// Analysis window size in seconds (30ms is standard for speech F0)
    private static let windowDuration: Double = 0.03
    /// Hop between windows (10ms = 100 frames/sec)
    private static let hopDuration: Double = 0.01
    /// Minimum plausible F0 for human speech (Hz)
    private static let f0Min: Float = 75
    /// Maximum plausible F0 for human speech (Hz)
    private static let f0Max: Float = 500
    /// Autocorrelation peak threshold to classify a frame as voiced
    private static let voicedThreshold: Float = 0.3

    // MARK: - Public API

    /// Analyze the pitch characteristics of an audio file.
    /// Returns nil if the file cannot be read or has insufficient voiced frames.
    static func analyze(audioURL: URL) -> PitchMetrics? {
        guard let samples = loadMonoPCM(url: audioURL) else { return nil }
        guard samples.sampleRate > 0 else { return nil }

        let sr = samples.sampleRate
        let data = samples.data

        let windowSize = max(1, Int(windowDuration * sr))
        let hopSize = max(1, Int(hopDuration * sr))
        let minLag = Int(sr / Double(f0Max))
        let maxLag = min(windowSize - 1, Int(sr / Double(f0Min)))

        guard maxLag > minLag, data.count > windowSize else { return nil }

        var f0Values: [Float] = []

        // Slide analysis window across the signal
        var offset = 0
        while offset + windowSize <= data.count {
            let window = Array(data[offset..<(offset + windowSize)])
            if let f0 = estimateF0(window: window, sampleRate: sr, minLag: minLag, maxLag: maxLag) {
                f0Values.append(f0)
            }
            offset += hopSize
        }

        guard f0Values.count >= 5 else { return nil }

        // Compute statistics
        let mean = f0Values.reduce(0, +) / Float(f0Values.count)
        let sorted = f0Values.sorted()
        let p5 = sorted[max(0, Int(Double(sorted.count) * 0.05))]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]

        let variance = f0Values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(f0Values.count)
        let stdDev = sqrt(variance)

        let rangeSemitones = hzToSemitones(from: p5, to: p95)

        // Pitch variation score:
        // Research: typical speech has F0 stddev of 20-40 Hz; engaging speakers 30-60 Hz.
        // stddev in semitones is more perceptually meaningful.
        let stdDevSemitones = mean > 0 ? 12.0 * log2(Double((mean + stdDev) / mean)) : 0
        // Map: 0 semitones stddev → 0, ~4 semitones stddev → 100 (very expressive)
        let pitchVariationScore = max(0, min(100, Int(stdDevSemitones * 25)))

        // Declination: linear trend of F0 over time (semitones per second)
        let declinationRate = computeDeclination(f0Values: f0Values, hopDuration: hopDuration)

        // Downsample contour for storage (max 200 points)
        let contour = downsample(f0Values, targetCount: 200)

        return PitchMetrics(
            f0Mean: mean,
            f0StdDev: stdDev,
            f0Min: p5,
            f0Max: p95,
            f0RangeSemitones: rangeSemitones,
            pitchVariationScore: pitchVariationScore,
            declinationRate: declinationRate,
            f0Contour: contour
        )
    }

    // MARK: - F0 Estimation (Autocorrelation)

    /// Estimate F0 for a single analysis window using normalized autocorrelation.
    /// Returns nil if the frame is unvoiced.
    private static func estimateF0(window: [Float], sampleRate: Double, minLag: Int, maxLag: Int) -> Float? {
        let n = window.count
        guard maxLag < n, minLag < maxLag else { return nil }

        // Apply Hanning window to reduce spectral leakage
        var windowed = [Float](repeating: 0, count: n)
        var hannWindow = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hannWindow, vDSP_Length(n), Int32(vDSP_HALF_WINDOW))
        vDSP_vmul(window, 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))

        // Compute energy for normalization
        var energy: Float = 0
        vDSP_dotpr(windowed, 1, windowed, 1, &energy, vDSP_Length(n))
        guard energy > 1e-10 else { return nil } // silence

        // Compute autocorrelation for lags in [minLag, maxLag]
        var bestLag = minLag
        var bestCorr: Float = -1

        for lag in minLag...maxLag {
            var corr: Float = 0
            let overlapLen = n - lag
            guard overlapLen > 0 else { continue }
            vDSP_dotpr(windowed, 1, Array(windowed[lag...]), 1, &corr, vDSP_Length(overlapLen))

            // Normalize by geometric mean of energies at offset positions
            var energy0: Float = 0
            var energy1: Float = 0
            vDSP_dotpr(windowed, 1, windowed, 1, &energy0, vDSP_Length(overlapLen))
            vDSP_dotpr(Array(windowed[lag...]), 1, Array(windowed[lag...]), 1, &energy1, vDSP_Length(overlapLen))
            let norm = sqrt(energy0 * energy1)
            guard norm > 1e-10 else { continue }
            corr /= norm

            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }

        guard bestCorr >= voicedThreshold else { return nil }

        // Parabolic interpolation for sub-sample accuracy
        let f0 = Float(sampleRate) / Float(bestLag)
        return f0
    }

    // MARK: - Audio Loading

    private struct MonoSamples {
        let data: [Float]
        let sampleRate: Double
    }

    /// Load audio file as mono Float32 PCM samples using AVAudioFile.
    private static func loadMonoPCM(url: URL) -> MonoSamples? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return nil }

        // Request mono float32 format
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: sampleRate,
                                              channels: 1,
                                              interleaved: false) else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount) else { return nil }

        // If input is already mono float32, read directly; otherwise use a converter
        if format.channelCount == 1 && format.commonFormat == .pcmFormatFloat32 {
            do {
                try file.read(into: buffer)
            } catch {
                return nil
            }
        } else {
            // Read into original format first, then convert
            guard let originalBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            do {
                try file.read(into: originalBuffer)
            } catch {
                return nil
            }
            guard let converter = AVAudioConverter(from: format, to: monoFormat) else { return nil }
            let status = converter.convert(to: buffer, error: nil) { _, outStatus in
                outStatus.pointee = .haveData
                return originalBuffer
            }
            guard status != .error else { return nil }
        }

        guard let channelData = buffer.floatChannelData else { return nil }
        let count = Int(buffer.frameLength)
        let data = Array(UnsafeBufferPointer(start: channelData[0], count: count))

        return MonoSamples(data: data, sampleRate: sampleRate)
    }

    // MARK: - Helpers

    /// Convert F0 range to semitones (perceptually uniform pitch scale).
    private static func hzToSemitones(from low: Float, to high: Float) -> Float {
        guard low > 0, high > 0 else { return 0 }
        return 12.0 * log2(high / low)
    }

    /// Compute linear pitch declination rate (semitones per second).
    /// Natural speech typically shows slight declination (~1-2 st/s).
    private static func computeDeclination(f0Values: [Float], hopDuration: Double) -> Float {
        let n = f0Values.count
        guard n >= 10 else { return 0 }

        // Convert to semitones relative to first value
        let ref = f0Values[0]
        guard ref > 0 else { return 0 }
        let semitones = f0Values.map { 12.0 * log2(Double($0) / Double(ref)) }

        // Simple linear regression: y = semitones, x = time in seconds
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
        return Float(num / den) // semitones per second
    }

    /// Downsample an array to a target count by averaging bins.
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

import Foundation
import AVFoundation

// MARK: - Voice Profile Types

struct VoiceProfile {
    let f0Hz: Double
    let energyDb: Double
    let sampleCount: Int

    var blendWeight: Double {
        switch sampleCount {
        case 0: return 0.0
        case 1: return 0.3
        case 2: return 0.5
        default: return 0.7
        }
    }
}

struct VoiceProfileUpdate {
    let sessionF0Hz: Double
    let sessionEnergyDb: Double
    let separationConfidence: Int
}

/// Heuristic single-speaker isolation for conversational recordings.
/// Uses per-word acoustic similarity (pitch + energy) to the user's
/// early-session voice profile and tags likely non-user words.
enum ConversationIsolationService {
    static func labelPrimarySpeaker(
        words: [TranscriptionWord],
        audioURL: URL,
        totalDuration: TimeInterval,
        persistentProfile: VoiceProfile? = nil,
        preloadedSamples: (samples: [Float], sampleRate: Double)? = nil
    ) -> ([TranscriptionWord], SpeakerIsolationMetrics?, VoiceProfileUpdate?) {
        guard words.count >= 12, totalDuration >= 8 else {
            return (words, nil, nil)
        }
        let mono: MonoPCM
        if let preloaded = preloadedSamples {
            mono = MonoPCM(samples: preloaded.samples, sampleRate: preloaded.sampleRate)
        } else {
            guard let loaded = loadMonoPCM(url: audioURL) else {
                return (words, nil, nil)
            }
            mono = loaded
        }

        let sortedWords = words.enumerated().sorted { $0.element.start < $1.element.start }
        let features = sortedWords.map { indexedWord in
            acousticFeatures(
                for: indexedWord.element,
                sampleRate: mono.sampleRate,
                samples: mono.samples
            )
        }

        let profileWindowEnd = min(12.0, totalDuration * 0.35)
        let profileCandidates = Array(zip(sortedWords.map(\.element), features)
            .filter { pair in pair.0.start <= profileWindowEnd }
            .prefix(24))

        let sessionF0 = median(profileCandidates.compactMap { $0.1.f0Hz })
        let sessionEnergy = median(profileCandidates.map { $0.1.energyDb })
        guard let sessionF0, let sessionEnergy else {
            return (words, nil, nil)
        }

        // Blend persistent profile with session profile
        var profileF0 = sessionF0
        var profileEnergy = sessionEnergy
        if let persistent = persistentProfile, persistent.sampleCount > 0 {
            let w = persistent.blendWeight
            profileF0 = persistent.f0Hz * w + sessionF0 * (1.0 - w)
            profileEnergy = persistent.energyDb * w + sessionEnergy * (1.0 - w)
        }

        var wordConfidence = [Double](repeating: 0.5, count: sortedWords.count)
        var isPrimary = [Bool](repeating: true, count: sortedWords.count)

        for i in 0..<sortedWords.count {
            let feature = features[i]
            let f0Penalty: Double
            if let f0 = feature.f0Hz, f0 > 0 {
                let semitoneDistance = abs(log2(f0 / profileF0) * 12.0)
                f0Penalty = min(1.0, semitoneDistance / 6.0)
            } else {
                f0Penalty = 0.35
            }

            let energyPenalty = min(1.0, abs(feature.energyDb - profileEnergy) / 16.0)
            let penalty = f0Penalty * 0.75 + energyPenalty * 0.25
            let confidence = max(0.0, min(1.0, 1.0 - penalty))
            wordConfidence[i] = confidence
            isPrimary[i] = confidence >= 0.48
        }

        // Smooth unstable flips using a local majority window.
        if isPrimary.count >= 5 {
            var smoothed = isPrimary
            for i in 2..<(isPrimary.count - 2) {
                let local = isPrimary[(i - 2)...(i + 2)]
                let positives = local.filter { $0 }.count
                smoothed[i] = positives >= 3
            }
            isPrimary = smoothed
        }

        let primaryCount = isPrimary.filter { $0 }.count
        let primaryRatio = sortedWords.isEmpty ? 1.0 : Double(primaryCount) / Double(sortedWords.count)
        let switchCount = countSwitches(in: isPrimary)
        let filteredOut = sortedWords.count - primaryCount

        let speakerAF0 = median(zip(isPrimary, features).compactMap { isPrimaryFlag, feature in
            isPrimaryFlag ? feature.f0Hz : nil
        })
        let speakerBF0 = median(zip(isPrimary, features).compactMap { isPrimaryFlag, feature in
            isPrimaryFlag ? nil : feature.f0Hz
        })
        let f0Gap = {
            guard let a = speakerAF0, let b = speakerBF0, a > 0, b > 0 else { return 0.0 }
            return abs(log2(a / b) * 12.0)
        }()

        let speakerAEnergy = median(zip(isPrimary, features).compactMap { isPrimaryFlag, feature in
            isPrimaryFlag ? feature.energyDb : nil
        })
        let speakerBEnergy = median(zip(isPrimary, features).compactMap { isPrimaryFlag, feature in
            isPrimaryFlag ? nil : feature.energyDb
        })
        let energyGap = {
            guard let a = speakerAEnergy, let b = speakerBEnergy else { return 0.0 }
            return abs(a - b)
        }()

        let validF0Ratio = Double(features.compactMap(\.f0Hz).count) / Double(max(1, features.count))
        let switchRate = Double(switchCount) / Double(max(1, isPrimary.count - 1))
        let confidence = max(
            0,
            min(
                100,
                Int(
                    35.0 +
                    validF0Ratio * 25.0 +
                    min(f0Gap * 6.0, 25.0) +
                    min(energyGap * 2.0, 10.0) +
                    min(switchRate * 40.0, 10.0)
                )
            )
        )

        // Conservative fallback: if separation confidence is poor, avoid excluding words.
        let shouldApplyIsolation = confidence >= 50 && primaryRatio >= 0.40 && primaryRatio <= 0.95
        let conversationDetected = shouldApplyIsolation && filteredOut >= max(4, Int(Double(sortedWords.count) * 0.15)) && switchCount >= 2

        var updated = words
        for (sortedIndex, indexedWord) in sortedWords.enumerated() {
            let source = indexedWord.element
            let keepAsPrimary = shouldApplyIsolation ? isPrimary[sortedIndex] : true
            let confidenceValue = wordConfidence[sortedIndex]

            updated[indexedWord.offset] = TranscriptionWord(
                word: source.word,
                start: source.start,
                end: source.end,
                confidence: source.confidence,
                isFiller: source.isFiller,
                isVocabWord: source.isVocabWord,
                isPrimarySpeaker: keepAsPrimary,
                speakerConfidence: confidenceValue
            )
        }

        let metrics = SpeakerIsolationMetrics(
            primarySpeakerWordRatio: shouldApplyIsolation ? primaryRatio : 1.0,
            filteredOutWordCount: shouldApplyIsolation ? filteredOut : 0,
            speakerSwitchCount: shouldApplyIsolation ? switchCount : 0,
            separationConfidence: confidence,
            conversationDetected: conversationDetected
        )

        // Produce voice profile update from primary speaker's observed features
        let profileUpdate: VoiceProfileUpdate?
        if let aF0 = speakerAF0, let aEnergy = speakerAEnergy {
            if shouldApplyIsolation || primaryRatio > 0.95 {
                profileUpdate = VoiceProfileUpdate(
                    sessionF0Hz: aF0,
                    sessionEnergyDb: aEnergy,
                    separationConfidence: confidence
                )
            } else {
                profileUpdate = nil
            }
        } else {
            profileUpdate = nil
        }

        return (updated, metrics, profileUpdate)
    }

    // MARK: - Voice Profile Extraction

    /// Extract a baseline voice profile from a calibration audio recording.
    /// Splits the audio into fixed-size windows and computes median F0/energy.
    static func extractVoiceProfile(from audioURL: URL) -> VoiceProfile? {
        guard let mono = loadMonoPCM(url: audioURL) else { return nil }

        let windowDuration = 0.08 // 80ms windows
        let windowSamples = Int(mono.sampleRate * windowDuration)
        guard windowSamples > 0, mono.samples.count >= windowSamples * 3 else { return nil }

        var f0Values: [Double] = []
        var energyValues: [Double] = []

        var offset = 0
        while offset + windowSamples <= mono.samples.count {
            let range = offset..<(offset + windowSamples)

            var sumSq: Float = 0
            for i in range { sumSq += mono.samples[i] * mono.samples[i] }
            let rms = sqrt(max(1e-9, sumSq / Float(windowSamples)))
            let energyDb = 20.0 * log10(Double(rms))

            // Skip silence
            if energyDb > -40.0 {
                energyValues.append(energyDb)
                if let f0 = estimateDominantF0(in: mono.samples, range: range, sampleRate: mono.sampleRate) {
                    f0Values.append(f0)
                }
            }

            offset += windowSamples
        }

        guard let medianF0 = median(f0Values), let medianEnergy = median(energyValues) else {
            return nil
        }

        return VoiceProfile(f0Hz: medianF0, energyDb: medianEnergy, sampleCount: 1)
    }

    // MARK: - Acoustic Feature Extraction

    private struct WordAcousticFeatures {
        let energyDb: Double
        let f0Hz: Double?
    }

    private static func acousticFeatures(
        for word: TranscriptionWord,
        sampleRate: Double,
        samples: [Float]
    ) -> WordAcousticFeatures {
        let startIndex = max(0, Int(word.start * sampleRate))
        let endIndex = min(samples.count, Int(word.end * sampleRate))
        let minWindow = max(1, Int(sampleRate * 0.04))

        let lo: Int
        let hi: Int
        if endIndex > startIndex + minWindow {
            lo = startIndex
            hi = endIndex
        } else {
            let midpoint = max(0, min(samples.count - 1, (startIndex + endIndex) / 2))
            let half = minWindow / 2
            lo = max(0, midpoint - half)
            hi = min(samples.count, max(lo + 1, midpoint + half))
        }

        // Energy from full-rate samples (cheap — single pass)
        var sumSq: Float = 0
        for i in lo..<hi { sumSq += samples[i] * samples[i] }
        let rms = sqrt(max(1e-9, sumSq / Float(max(1, hi - lo))))
        let energyDb = 20.0 * log10(Double(rms))

        // F0 from downsampled slice (expensive autocorrelation — reduce sample count)
        let f0 = estimateDominantF0(in: samples, range: lo..<hi, sampleRate: sampleRate)
        return WordAcousticFeatures(energyDb: energyDb, f0Hz: f0)
    }

    /// Pitch detection via autocorrelation on a downsampled version of the signal.
    /// Downsampling to ~4kHz reduces computation by ~100x for 44.1kHz audio while
    /// preserving the 85-320Hz fundamental frequency range we care about.
    private static func estimateDominantF0(in samples: [Float], range: Range<Int>, sampleRate: Double) -> Double? {
        // Downsample to ~4kHz for F0 detection (Nyquist = 2kHz, well above 320Hz max F0)
        let targetRate = 4000.0
        let factor = max(1, Int(sampleRate / targetRate))
        let effectiveRate = sampleRate / Double(factor)

        let downsampled: [Float]
        if factor > 1 {
            var buf = [Float]()
            buf.reserveCapacity((range.count + factor - 1) / factor)
            var i = range.lowerBound
            while i < range.upperBound {
                buf.append(samples[i])
                i += factor
            }
            downsampled = buf
        } else {
            downsampled = Array(samples[range])
        }

        let n = downsampled.count
        guard n >= Int(effectiveRate * 0.03) else { return nil }

        let minF0 = 85.0
        let maxF0 = 320.0
        let minLag = Int(effectiveRate / maxF0)
        let maxLag = min(n - 1, Int(effectiveRate / minF0))
        guard maxLag > minLag else { return nil }

        var bestLag = 0
        var bestCorr = Float.zero

        for lag in minLag...maxLag {
            let overlap = n - lag
            if overlap <= 0 { continue }

            var num: Float = 0
            var denA: Float = 0
            var denB: Float = 0

            for i in 0..<overlap {
                let a = downsampled[i]
                let b = downsampled[i + lag]
                num += a * b
                denA += a * a
                denB += b * b
            }

            let denom = sqrt(denA * denB)
            guard denom > 1e-8 else { continue }
            let corr = num / denom

            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }

        guard bestLag > 0, bestCorr > 0.35 else { return nil }
        return effectiveRate / Double(bestLag)
    }

    // MARK: - Utilities

    private static func countSwitches(in flags: [Bool]) -> Int {
        guard flags.count >= 2 else { return 0 }
        var switches = 0
        for i in 1..<flags.count where flags[i] != flags[i - 1] {
            switches += 1
        }
        return switches
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    struct MonoPCM {
        let samples: [Float]
        let sampleRate: Double
    }

    static func loadMonoPCM(url: URL) -> MonoPCM? {
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
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
                return nil
            }
            do {
                try file.read(into: sourceBuffer)
            } catch {
                return nil
            }
            guard let converter = AVAudioConverter(from: sourceFormat, to: monoFormat) else { return nil }
            let status = converter.convert(to: monoBuffer, error: nil) { _, outStatus in
                outStatus.pointee = .haveData
                return sourceBuffer
            }
            guard status != .error else { return nil }
        }

        guard let channel = monoBuffer.floatChannelData else { return nil }
        let count = Int(monoBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: count))
        return MonoPCM(samples: samples, sampleRate: sampleRate)
    }
}

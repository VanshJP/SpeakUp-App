import Foundation
import AVFoundation

/// Heuristic single-speaker isolation for conversational recordings.
/// Uses per-word acoustic similarity (pitch + energy) to the user's
/// early-session voice profile and tags likely non-user words.
enum ConversationIsolationService {
    static func labelPrimarySpeaker(
        words: [TranscriptionWord],
        audioURL: URL,
        totalDuration: TimeInterval
    ) -> ([TranscriptionWord], SpeakerIsolationMetrics?) {
        guard words.count >= 12, totalDuration >= 8 else {
            return (words, nil)
        }
        guard let mono = loadMonoPCM(url: audioURL) else {
            return (words, nil)
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

        let profileF0 = median(profileCandidates.compactMap { $0.1.f0Hz })
        let profileEnergy = median(profileCandidates.map { $0.1.energyDb })
        guard let profileF0, let profileEnergy else {
            return (words, nil)
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

        return (updated, metrics)
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

        let slice: ArraySlice<Float>
        if endIndex > startIndex + minWindow {
            slice = samples[startIndex..<endIndex]
        } else {
            let midpoint = max(0, min(samples.count - 1, (startIndex + endIndex) / 2))
            let half = minWindow / 2
            let lo = max(0, midpoint - half)
            let hi = min(samples.count, midpoint + half)
            slice = samples[lo..<max(lo + 1, hi)]
        }

        let rms = sqrt(max(1e-9, slice.reduce(Float(0)) { $0 + ($1 * $1) } / Float(max(1, slice.count))))
        let energyDb = 20.0 * log10(Double(rms))
        let f0 = estimateDominantF0(in: Array(slice), sampleRate: sampleRate)
        return WordAcousticFeatures(energyDb: energyDb, f0Hz: f0)
    }

    private static func estimateDominantF0(in samples: [Float], sampleRate: Double) -> Double? {
        let n = samples.count
        guard n >= Int(sampleRate * 0.03) else { return nil }

        let minF0 = 85.0
        let maxF0 = 320.0
        let minLag = Int(sampleRate / maxF0)
        let maxLag = min(n - 1, Int(sampleRate / minF0))
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
                let a = samples[i]
                let b = samples[i + lag]
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
        return sampleRate / Double(bestLag)
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

import Accelerate
import Foundation

/// Pulls each word's time range in to the speech actually inside it, so the
/// silences a speaker leaves become gaps between words.
///
/// `SpeechTranscriber` hands back word ranges that tile a phrase edge to
/// edge: a two-second pause after "that" comes back as a two-second "that".
/// Pause scoring, filler context ("like" after a pause) and phonation time
/// all read the gaps between words, so without this every mid-sentence pause
/// vanished. Whisper's word stamps did the same thing less often.
///
/// Energy only: a 10 ms frame is voiced when it sits clearly above the take's
/// own noise floor. Words only ever shrink inside their own range, never grow
/// or cross a neighbour, so a wrong call costs a slightly short word, never a
/// reordered transcript. A word with no voiced audio in its range keeps it:
/// better to miss a pause than to invent one out of soft speech.
nonisolated enum WordTimingRefiner {
    static let frameDuration: TimeInterval = 0.01
    /// Quiet shorter than this sits inside speech - a stop consonant, the dip
    /// between syllables - and is not a pause.
    static let minimumSilence: TimeInterval = 0.15
    /// A voiced stretch shorter than this is too thin to move a word onto.
    static let minimumWordDuration: TimeInterval = 0.05

    static func refine(_ words: [RawWordTiming], pcm: MonoPCM) -> [RawWordTiming] {
        refine(words, voiced: voicedFrames(in: pcm))
    }

    /// Moves each word onto the longest voiced run inside its range. Expects
    /// words sorted by start, as a transcript arrives.
    static func refine(_ words: [RawWordTiming], voiced: [Bool]) -> [RawWordTiming] {
        let runs = voicedRuns(voiced)
        guard !runs.isEmpty else { return words }

        var cursor = 0
        return words.map { word in
            let first = Int((word.start / frameDuration).rounded(.down))
            let last = Int((word.end / frameDuration).rounded(.up))
            guard last > first else { return word }

            // Words arrive sorted, so runs that end before this word never
            // matter again.
            while cursor < runs.count, runs[cursor].upperBound <= first { cursor += 1 }

            var best: Range<Int>?
            var index = cursor
            while index < runs.count, runs[index].lowerBound < last {
                let clipped = max(runs[index].lowerBound, first)..<min(runs[index].upperBound, last)
                if clipped.count > (best?.count ?? 0) { best = clipped }
                index += 1
            }

            guard let best,
                  Double(best.count) * frameDuration >= minimumWordDuration else { return word }
            return RawWordTiming(
                word: word.word,
                start: max(word.start, Double(best.lowerBound) * frameDuration),
                end: min(word.end, Double(best.upperBound) * frameDuration),
                confidence: word.confidence
            )
        }
    }

    /// One flag per 10 ms frame. The bar is the take's own noise floor (its
    /// 10th-percentile frame) plus a margin that grows with how far speech
    /// rises above it, so a quiet room and a noisy one both split cleanly.
    static func voicedFrames(in pcm: MonoPCM) -> [Bool] {
        let frameLength = Int(pcm.sampleRate * frameDuration)
        guard frameLength > 0, pcm.samples.count >= frameLength else { return [] }

        let frameCount = pcm.samples.count / frameLength
        var levels = [Float](repeating: 0, count: frameCount)
        pcm.samples.withUnsafeBufferPointer { samples in
            for frame in 0..<frameCount {
                var meanSquare: Float = 0
                vDSP_measqv(samples.baseAddress! + frame * frameLength, 1, &meanSquare, vDSP_Length(frameLength))
                levels[frame] = 10 * log10(max(meanSquare, 1e-10))
            }
        }

        let sorted = levels.sorted()
        // Digital silence at the edges would drag the floor to -100 dB and
        // make room noise read as speech.
        let floor = max(sorted[sorted.count / 10], -80)
        let peak = sorted[min(sorted.count - 1, sorted.count * 95 / 100)]
        let threshold = floor + max(6, (peak - floor) * 0.25)
        return levels.map { $0 > threshold }
    }

    /// Voiced frame ranges, with silences shorter than `minimumSilence`
    /// bridged so one word stays one run.
    static func voicedRuns(_ voiced: [Bool]) -> [Range<Int>] {
        let bridge = Int((minimumSilence / frameDuration).rounded())
        var runs: [Range<Int>] = []
        var runStart: Int?

        for (frame, isVoiced) in voiced.enumerated() {
            switch (isVoiced, runStart) {
            case (true, nil):
                runStart = frame
            case (false, let start?):
                runs.append(start..<frame)
                runStart = nil
            default:
                break
            }
        }
        if let start = runStart { runs.append(start..<voiced.count) }

        var merged: [Range<Int>] = []
        for run in runs {
            if let previous = merged.last, run.lowerBound - previous.upperBound < bridge {
                merged[merged.count - 1] = previous.lowerBound..<run.upperBound
            } else {
                merged.append(run)
            }
        }
        return merged
    }
}

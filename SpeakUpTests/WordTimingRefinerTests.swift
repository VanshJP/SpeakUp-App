import Testing
import Foundation
@testable import SpeakUp

@MainActor
struct WordTimingRefinerTests {
    /// 10 ms frames: `true` for every frame inside the given second ranges.
    private func mask(seconds: Double, voiced ranges: [ClosedRange<Double>]) -> [Bool] {
        (0..<Int(seconds * 100)).map { frame in
            let time = Double(frame) / 100
            return ranges.contains { $0.contains(time) }
        }
    }

    @Test func pauseInsideATiledWordBecomesAGap() {
        // SpeechTranscriber tiles "that" across the pause that follows it.
        let words = [
            RawWordTiming(word: "think", start: 0.0, end: 0.5),
            RawWordTiming(word: "that", start: 0.5, end: 2.6),
            RawWordTiming(word: "discipline", start: 2.6, end: 3.4)
        ]
        let voiced = mask(seconds: 4, voiced: [0.0...0.8, 2.6...3.4])

        let refined = WordTimingRefiner.refine(words, voiced: voiced)

        #expect(refined[1].start == 0.5)
        #expect(abs(refined[1].end - 0.81) < 0.02)
        #expect(refined[2].start - refined[1].end > 1.7)
    }

    @Test func wordMovesOntoItsLongestVoicedRun() {
        // A breath blip at the front of the range must not claim the word.
        let words = [RawWordTiming(word: "discipline", start: 1.0, end: 3.0)]
        let voiced = mask(seconds: 3, voiced: [1.0...1.1, 2.2...3.0])

        let refined = WordTimingRefiner.refine(words, voiced: voiced)

        #expect(abs(refined[0].start - 2.2) < 0.02)
        #expect(refined[0].end == 3.0)
    }

    @Test func shortDipsInsideSpeechAreNotPauses() {
        // A 100 ms stop closure between syllables stays inside the word.
        let words = [RawWordTiming(word: "practice", start: 0.0, end: 0.6)]
        let voiced = mask(seconds: 1, voiced: [0.0...0.25, 0.36...0.6])

        let refined = WordTimingRefiner.refine(words, voiced: voiced)

        #expect(refined[0].start == 0.0)
        #expect(abs(refined[0].end - 0.6) < 0.02)
    }

    @Test func wordsOnlyShrinkAndKeepTheirOrder() {
        let words = (0..<20).map { index in
            RawWordTiming(word: "w\(index)", start: Double(index) * 0.4, end: Double(index + 1) * 0.4)
        }
        let voiced = mask(seconds: 8, voiced: [0.1...1.9, 3.0...5.5, 6.2...7.9])

        let refined = WordTimingRefiner.refine(words, voiced: voiced)

        for (before, after) in zip(words, refined) {
            #expect(after.word == before.word)
            #expect(after.start >= before.start)
            #expect(after.end <= before.end)
            #expect(after.end > after.start)
        }
    }

    @Test func silentWordKeepsItsRange() {
        let words = [RawWordTiming(word: "mm", start: 1.0, end: 1.4)]
        let refined = WordTimingRefiner.refine(words, voiced: mask(seconds: 2, voiced: [0.0...0.5]))
        #expect(refined[0].start == 1.0)
        #expect(refined[0].end == 1.4)
    }

    @Test func voicingFollowsTheTakesOwnNoiseFloor() {
        // Quiet room hiss with two tone bursts, at a phone recorder's rate.
        let sampleRate = 16_000.0
        var samples = (0..<Int(sampleRate * 3)).map { _ in Float.random(in: -0.002...0.002) }
        for burst in [0.5...1.0, 2.0...2.4] {
            for index in Int(burst.lowerBound * sampleRate)..<Int(burst.upperBound * sampleRate) {
                samples[index] += 0.3 * sin(Float(index) * 2 * .pi * 180 / Float(sampleRate))
            }
        }

        let voiced = WordTimingRefiner.voicedFrames(in: MonoPCM(samples: samples, sampleRate: sampleRate))
        let runs = WordTimingRefiner.voicedRuns(voiced)

        #expect(runs.count == 2)
        #expect(abs(runs[0].lowerBound - 50) <= 1)
        #expect(abs(runs[0].upperBound - 100) <= 1)
        #expect(abs(runs[1].lowerBound - 200) <= 1)
        #expect(abs(runs[1].upperBound - 240) <= 1)
    }
}

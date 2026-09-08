import Testing
import Foundation
@testable import SpeakUp


struct PaceSeriesTests {

    private func take(
        duration: TimeInterval,
        pauseFraction: Double,
        articulation: Double,
        burst: TimeInterval = 4.0
    ) -> [TranscriptionWord] {
        var words: [TranscriptionWord] = []
        var t: TimeInterval = 0.5
        let gap = burst * (pauseFraction / (1 - pauseFraction))
        while t < duration {
            let end = min(t + burst, duration)
            while t < end {
                words.append(TranscriptionWord(word: "word", start: t, end: t + 0.5 / articulation))
                t += 1 / articulation
            }
            t += gap
        }
        return words
    }

    private func gross(_ words: [TranscriptionWord], _ duration: TimeInterval) -> Double {
        Double(words.count) / (duration / 60)
    }

    @Test func peakStaysNearTheGrossRateOnAPausedTake() {
        let duration: TimeInterval = 60
        let words = take(duration: duration, pauseFraction: 0.45, articulation: 5.0)
        let series = SpeechAnalysisPipeline.computeWPMTimeSeries(words: words, actualDuration: duration)

        let peak = series.map(\.wpm).max() ?? 0
        let headline = gross(words, duration)

        #expect(headline < 200)
        #expect(peak < headline * 1.35)
        #expect(peak < 250)
    }

    @Test func seriesCoversTheWholeTakeWithoutDuplicatePoints() {
        for duration in [12.0, 30.0, 45.0, 60.0, 125.0] as [TimeInterval] {
            let words = take(duration: duration, pauseFraction: 0.3, articulation: 4.5)
            let series = SpeechAnalysisPipeline.computeWPMTimeSeries(words: words, actualDuration: duration)

            #expect(series.count >= 2, "duration \(duration) produced \(series.count) points")
            let stamps = series.map(\.timestamp)
            #expect(stamps == stamps.sorted())
            #expect(Set(stamps).count == stamps.count)
            #expect(series.last!.timestamp < duration)
            #expect(series.allSatisfy { $0.timestamp > 0 })
        }
    }

    @Test func steadySpeechReportsAFlatLine() {
        let duration: TimeInterval = 60
        // 150 WPM with no pauses at all: every window must read 150.
        let words = (0..<150).map { i in
            TranscriptionWord(word: "w", start: Double(i) * 0.4, end: Double(i) * 0.4 + 0.3)
        }
        let series = SpeechAnalysisPipeline.computeWPMTimeSeries(words: words, actualDuration: duration)

        for point in series {
            #expect(abs(point.wpm - 150) < 8, "window at \(point.timestamp) read \(point.wpm)")
        }
    }

    @Test func degenerateInputsProduceNothing() {
        #expect(SpeechAnalysisPipeline.computeWPMTimeSeries(words: [], actualDuration: 60).isEmpty)
        #expect(SpeechAnalysisPipeline.computeWPMTimeSeries(
            words: [TranscriptionWord(word: "hi", start: 0, end: 0.3)],
            actualDuration: 0
        ).isEmpty)
    }
}

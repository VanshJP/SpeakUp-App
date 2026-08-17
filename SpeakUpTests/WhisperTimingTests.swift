import Testing
import Foundation
@testable import SpeakUp

// Whisper occasionally emits a word whose end timestamp overshoots by minutes.
// Normalization used to carry that overshoot forward, collapsing every later
// word into a sliver at the wrong offset — a transcript whose second half no
// longer matched the audio.

@MainActor
struct WhisperTimingTests {
    private func timing(_ word: String, _ start: TimeInterval, _ end: TimeInterval) -> RawWordTiming {
        RawWordTiming(word: word, start: start, end: end, confidence: 1.0)
    }

    @Test func normalWordsKeepTheirTimings() {
        let input = [timing("today", 0, 0.4), timing("went", 0.5, 0.9)]
        let output = WhisperService.normalizeTimings(input)

        #expect(output.map(\.start) == [0, 0.5])
        #expect(output.map(\.end) == [0.4, 0.9])
    }

    @Test func overshootingEndDoesNotDragLaterWords() {
        let input = [
            timing("first", 0, 0.4),
            timing("runaway", 0.5, 300),
            timing("second", 1.0, 1.4),
            timing("third", 1.5, 1.9)
        ]
        let output = WhisperService.normalizeTimings(input)

        // The bad word is capped, and everything after it keeps its own place.
        #expect(output[1].end <= 1.0)
        #expect(output[2].start == 1.0)
        #expect(output[3].start == 1.5)
        #expect(output.last!.end == 1.9)
    }

    @Test func overlapsAndZeroLengthWordsStillGetFixed() {
        let input = [
            timing("overlap", 0, 0.8),
            timing("next", 0.5, 0.9),
            timing("empty", 1.0, 1.0)
        ]
        let output = WhisperService.normalizeTimings(input)

        #expect(output[0].end <= output[1].start)
        #expect(output.allSatisfy { $0.end > $0.start })
        for (previous, next) in zip(output, output.dropFirst()) {
            #expect(next.start >= previous.start)
        }
    }
}

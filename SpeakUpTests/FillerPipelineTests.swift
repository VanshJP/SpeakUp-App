import Testing
import Foundation
@testable import SpeakUp

// FillerDetectionPipeline is shared by Whisper, Apple Speech, and the live
// counter — one regression here miscounts fillers on every surface at once.

@MainActor
struct FillerPipelineTests {
    /// Evenly spaced words with small gaps (no pauses, no sentence boundaries).
    private func timings(_ list: [String], gap: TimeInterval = 0.1) -> [RawWordTiming] {
        var cursor: TimeInterval = 0
        return list.map { word in
            let start = cursor
            let end = start + 0.3
            cursor = end + gap
            return RawWordTiming(word: word, start: start, end: end)
        }
    }

    @Test func hesitationSoundsAreAlwaysFillers() {
        let tagged = FillerDetectionPipeline.tagFillers(in: timings(["um", "uh", "hmm"]))
        #expect(tagged.allSatisfy(\.isFiller))
    }

    @Test func regularWordsAreNotFillers() {
        let tagged = FillerDetectionPipeline.tagFillers(in: timings(["today", "went", "great"]))
        #expect(tagged.allSatisfy { !$0.isFiller })
    }

    @Test func mixedSpeechTagsOnlyTheFillers() {
        let tagged = FillerDetectionPipeline.tagFillers(in: timings(["um", "today", "went", "uh", "great"]))
        #expect(tagged.filter(\.isFiller).map(\.word) == ["um", "uh"])
    }

    @Test func fillerPhraseTagsBothWords() {
        let tagged = FillerDetectionPipeline.tagFillers(in: timings(["you", "know", "practice"]))
        #expect(tagged[0].isFiller)
        #expect(tagged[1].isFiller)
        #expect(!tagged[2].isFiller)
    }

    @Test func timingsSurviveThePipeline() {
        let input = timings(["um", "speech"])
        let tagged = FillerDetectionPipeline.tagFillers(in: input)
        #expect(tagged.count == input.count)
        #expect(tagged[0].start == input[0].start)
        #expect(tagged[1].end == input[1].end)
    }

    @Test func emptyInputYieldsEmptyOutput() {
        #expect(FillerDetectionPipeline.tagFillers(in: []).isEmpty)
    }

    @Test func userRemovedDefaultIsRespected() {
        let config = FillerWordConfig(customFillers: [], customContextFillers: [], removedDefaults: ["um"])
        let tagged = FillerDetectionPipeline.tagFillers(in: timings(["um", "uh"]), config: config)
        #expect(!tagged[0].isFiller)
        #expect(tagged[1].isFiller)
    }
}

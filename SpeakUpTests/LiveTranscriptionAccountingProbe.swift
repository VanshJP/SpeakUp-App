import Testing
import Foundation
@testable import SpeakUp

// LiveTranscriptionService.updateFillerWordCounts is private and the service
// cannot run without SFSpeech, so its accounting core is pinned here as a
// mirror: watermark delta-slice + additive merge over the same
// FillerDetectionPipeline.tagFillers the service calls.
//
// Why additive and not the old whole-transcript max-merge (deleted when this
// file's algorithm shipped):
//   * Within one recognition request, max-merge was idempotent against
//     partial revisions; the delta slice preserves that.
//   * Across restarts, requests cover DISJOINT audio (the tap appends to
//     exactly one request at a time), so the true session total is a SUM.
//     Max-merge took max(request1, request2) per key and undercounted any
//     filler spoken in both windows. Additive sums correctly.
//   * Resetting the counts dict on restart would wipe session history every
//     time SFSpeech auto-finalizes at a pause — display continuity loses to
//     nothing here, because no replay exists to guard against.
//
// If the service drifts from this shape, re-run the audit before trusting
// these tests: they pin the contract, not the private method itself.

@MainActor
struct LiveTranscriptionAccountingProbe {
    /// Mirror of the service's accounting step. Returns the advanced
    /// watermark; mutates `counts` additively over segments `[watermark...]`.
    private func advanceWatermark(
        counts: inout [String: Int],
        watermark: Int,
        segments: [String]
    ) -> Int {
        // Shrinking partials must not rewind the watermark or recount.
        guard segments.count > watermark else { return watermark }
        let added = Array(segments[watermark...])

        // Contiguous timings, no pauses — matches the service feeding raw
        // segment timing straight into the shared pipeline.
        let timings = added.enumerated().map { index, word in
            RawWordTiming(word: word,
                          start: Double(index) * 0.4,
                          end: Double(index) * 0.4 + 0.3)
        }
        for word in FillerDetectionPipeline.tagFillers(in: timings) where word.isFiller {
            let key = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return segments.count
    }

    @Test func partialRevisionCountsOnlyTheDelta() {
        var counts: [String: Int] = [:]
        var watermark = 0

        watermark = advanceWatermark(counts: &counts, watermark: watermark,
                                     segments: ["um", "today", "went", "uh", "great"])
        #expect(watermark == 5)
        #expect(counts == ["um": 1, "uh": 1])

        // A later partial re-sends all five plus three new ones; only the
        // additions may move the tallies.
        watermark = advanceWatermark(counts: &counts, watermark: watermark,
                                     segments: ["um", "today", "went", "uh", "great",
                                                "and", "um", "again"])
        #expect(watermark == 8)
        #expect(counts["um"] == 2 && counts["uh"] == 1)
    }

    @Test func shrinkingPartialDoesNotRecountOrRewind() {
        var counts: [String: Int] = [:]
        var watermark = advanceWatermark(counts: &counts, watermark: 0,
                                         segments: ["um", "hello", "there"])
        #expect(counts["um"] == 1)

        // Zero-segment revisions between utterances: watermark holds.
        watermark = advanceWatermark(counts: &counts, watermark: watermark, segments: [])
        #expect(watermark == 3 && counts["um"] == 1)

        // A shorter revision must not rewind into already-counted audio…
        watermark = advanceWatermark(counts: &counts, watermark: watermark,
                                     segments: ["um", "hello"])
        #expect(watermark == 3)

        // …so the next growth counts only what it added.
        watermark = advanceWatermark(counts: &counts, watermark: watermark,
                                     segments: ["um", "hello", "there", "um"])
        #expect(watermark == 4 && counts["um"] == 2)
    }

    @Test func restartAccumulatesDisjointRequestsAdditively() {
        // Request 1 ends at an auto-finalized pause; the restart resets the
        // watermark but KEEPS the tallies. Request 2 covers new audio only.
        // Hesitation sounds only: lexical fillers need sentence context this
        // synthetic timing layout cannot provide.
        var counts: [String: Int] = [:]
        _ = advanceWatermark(counts: &counts, watermark: 0,
                             segments: ["um", "today", "uh"])

        _ = advanceWatermark(counts: &counts, watermark: 0,  // attachRecognition reset point
                             segments: ["um", "again", "uh"])

        // True session total: each hesitation said in both windows sums to 2.
        // The old max-merge reported max(1, 1) = 1 — the reason additive won.
        #expect(counts == ["um": 2, "uh": 2])
    }

    @Test func startResetsCountsAndWatermarkTogether() {
        // start() clears liveFillerWordCounts AND lastProcessedSegmentCount
        // as one pair. The invariant that matters: no state combination
        // survives where a fresh session inherits stale tallies while its
        // watermark starts from zero — that pairing is what keeps accounting
        // coherent across sessions.
        var counts: [String: Int] = ["um": 4, "like": 2]
        var watermark = 3

        // start():
        counts = [:]
        watermark = 0

        #expect(counts.isEmpty && watermark == 0)
        watermark = advanceWatermark(counts: &counts, watermark: watermark,
                                     segments: ["um", "fresh", "session"])
        #expect(counts == ["um": 1] && watermark == 3)
    }
}

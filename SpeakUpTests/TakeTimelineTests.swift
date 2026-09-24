import Testing
@testable import SpeakUp

struct TakeTimelineTests {

    private func word(_ text: String, _ start: Double, _ end: Double, filler: Bool = false, primary: Bool = true) -> TranscriptionWord {
        TranscriptionWord(word: text, start: start, end: end, isFiller: filler, isPrimarySpeaker: primary)
    }

    @Test("Micro-gaps fold into speech, real gaps become pauses, fillers get their own lane")
    func segments() {
        let timeline = TakeTimeline(words: [
            word("So", 0.5, 0.8),
            word("we", 0.9, 1.1),              // 0.1s gap: same run
            word("um", 1.2, 1.5, filler: true),
            word("shipped.", 1.6, 2.0),
            word("Then", 2.8, 3.0),            // 0.8s after a full stop: pause
            word("the", 3.1, 3.3),
            word("team", 5.0, 5.3),            // 1.7s mid-sentence: long pause
        ], duration: 6)

        #expect(timeline.segments.map(\.kind) == [.speaking, .filler, .speaking, .pause, .speaking, .longPause, .speaking])
        #expect(timeline.segments.first?.start == 0.5)
        #expect(timeline.segments.last?.end == 5.3)
        // Contiguous from first word to last: every segment starts where the last ended.
        for (a, b) in zip(timeline.segments, timeline.segments.dropFirst()) {
            #expect(a.end == b.start)
        }
        #expect(timeline.longPauseCount == 1)
        #expect(timeline.duration == 6)
    }

    @Test("Disabled tracking drops the lane and folds fillers into speech")
    func respectsSettings() {
        let words = [word("um", 0, 0.3, filler: true), word("hi.", 0.4, 0.6), word("Yes", 2, 2.2)]
        let timeline = TakeTimeline(words: words, duration: 3, showsPauses: false, showsFillers: false)

        #expect(timeline.lanes == [.speaking])
        #expect(timeline.segments.map(\.kind) == [.speaking, .speaking])
    }

    @Test("Another speaker's turn is blank, not a pause")
    func otherSpeaker() {
        let timeline = TakeTimeline(words: [
            word("Hi", 0, 0.3),
            word("question", 1, 1.5, primary: false),
            word("Answer", 3, 3.4),
        ], duration: 4)

        #expect(timeline.segments.map(\.kind) == [.speaking, .speaking])
    }

    @Test("A tap seeks a beat before the moment it lands on")
    func seek() {
        let timeline = TakeTimeline(words: [word("Hello", 2, 2.5), word("there", 4, 4.5)], duration: 5)

        #expect(timeline.seekTime(at: 3) == 2.0)     // inside the pause 2.5-4.0
        #expect(timeline.seekTime(at: 4.2) == 3.5)
        #expect(timeline.seekTime(at: 0.2) == 0)     // before the first word, clamped
    }
}

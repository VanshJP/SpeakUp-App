import Testing
@testable import SpeakUp

/// A story take is long enough for the script: the reading estimate plus 15%
/// headroom, rounded up to a take length, never under a minute.
@MainActor
@Suite("Story practice duration")
struct StoryPracticeDurationTests {
    @Test("Short and empty scripts get the one-minute floor")
    func floor() {
        #expect(Story(estimatedDurationSeconds: 0).practiceDuration == .sixty)
        #expect(Story(estimatedDurationSeconds: 40).practiceDuration == .sixty)
    }

    @Test("Longer scripts round up past the estimate with headroom")
    func roundsUp() {
        // 80s × 1.15 = 92s → 2 min (1.5 min is 90s, too short).
        #expect(Story(estimatedDurationSeconds: 80).practiceDuration == .onetwenty)
        // 150s × 1.15 = 172.5s → 3 min.
        #expect(Story(estimatedDurationSeconds: 150).practiceDuration == .threeMinutes)
    }

    @Test("Anything past the longest take caps at ten minutes")
    func caps() {
        #expect(Story(estimatedDurationSeconds: 900).practiceDuration == .tenMinutes)
    }
}

import Testing
import Foundation
@testable import SpeakUp

/// The reminder slot is derived, so these are the rules that keep it honest:
/// it follows the user, it arrives before them, and it refuses to guess when
/// there is nothing to go on.
struct PracticeRhythmTests {
    private let calendar = Calendar.current
    private let now = Date()

    /// A session `daysAgo` days back, at `hour`:`minute` local time.
    private func session(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @Test func noHistoryMeansNoSuggestion() {
        #expect(PracticeRhythm.suggestion(from: [], now: now) == nil)
    }

    /// The headline behaviour: practise at 19:00, get nudged at 18:30.
    @Test func reminderLandsOneLeadBeforeTheUsualTime() throws {
        let dates = (1...6).map { session(daysAgo: $0, hour: 19) }
        let suggestion = try #require(PracticeRhythm.suggestion(from: dates, now: now))

        #expect(suggestion.typicalHour == 19)
        #expect(suggestion.typicalMinute == 0)
        #expect(suggestion.hour == 18)
        #expect(suggestion.minute == 30)
    }

    /// Times of day wrap. Averaging 23:50 and 00:10 arithmetically lands at
    /// noon, which would put a midnight practitioner's reminder in the middle
    /// of their working day.
    @Test func timesAverageAroundMidnightNotThroughNoon() throws {
        let dates = [
            session(daysAgo: 1, hour: 23, minute: 50),
            session(daysAgo: 2, hour: 0, minute: 10),
            session(daysAgo: 3, hour: 23, minute: 50),
            session(daysAgo: 4, hour: 0, minute: 10)
        ]
        let suggestion = try #require(PracticeRhythm.suggestion(from: dates, now: now))

        // The mean sits on midnight, give or take the rounding, and nowhere
        // near the noon an arithmetic mean would have produced.
        #expect(suggestion.typicalHour == 0 || suggestion.typicalHour == 23)
        // Midnight minus thirty minutes is late evening, not a negative hour.
        #expect(suggestion.hour == 23)
    }

    /// Someone who practises at a different hour every day has no rhythm, and
    /// moving their reminder daily is churn, not personalization.
    @Test func scatteredHistoryKeepsTheStoredTime() {
        let dates = [2, 8, 14, 20].enumerated().map { session(daysAgo: $0.offset + 1, hour: $0.element) }
        #expect(PracticeRhythm.suggestion(from: dates, now: now) == nil)
    }

    /// Under the session floor there is nothing to be concentrated *about*, so
    /// one real data point is allowed to seed the slot. A default nobody chose
    /// is the thing being replaced.
    @Test func aSingleSessionStillSeedsTheSlot() throws {
        let suggestion = try #require(
            PracticeRhythm.suggestion(from: [session(daysAgo: 0, hour: 7, minute: 15)], now: now)
        )
        #expect(suggestion.hour == 6)
        #expect(suggestion.minute == 45)
    }

    /// Recency weighting: a habit that moved should be followed, not averaged
    /// against the one it replaced.
    @Test func recentSessionsOutweighOldOnes() throws {
        let old = (40...50).map { session(daysAgo: $0, hour: 8) }
        let recent = (0...6).map { session(daysAgo: $0, hour: 20) }
        let suggestion = try #require(PracticeRhythm.suggestion(from: old + recent, now: now))

        #expect(suggestion.typicalHour >= 19)
        #expect(suggestion.typicalHour <= 20)
    }

    /// Identical times are maximally concentrated; the number is reported so
    /// copy can talk about how settled a rhythm is.
    @Test func concentrationPeaksOnIdenticalTimes() throws {
        let dates = (1...5).map { session(daysAgo: $0, hour: 12) }
        let suggestion = try #require(PracticeRhythm.suggestion(from: dates, now: now))
        #expect(suggestion.concentration > 0.99)
    }
}

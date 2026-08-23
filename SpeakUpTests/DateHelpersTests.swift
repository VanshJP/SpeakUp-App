import Testing
import Foundation
@testable import SpeakUp

// Streak arithmetic sits on the retention-critical path (notifications,
// widgets, achievements) — every edge below has a user-visible consequence.

struct StreakCalculationTests {
    // calculateStreak reads Date() internally (no injectable now), so fully
    // absolute fixtures are impossible. Pin one start-of-day anchor and derive
    // every fixture in whole days — nothing can straddle a midnight/DST edge.
    private static let today = Calendar.current.startOfDay(for: Date())

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Self.today)!
    }

    @Test func emptyDatesIsZero() {
        #expect(Date.calculateStreak(from: []) == 0)
    }

    @Test func practicedTodayIsOne() {
        #expect(Date.calculateStreak(from: [Self.today]) == 1)
    }

    @Test func yesterdayOnlyKeepsStreakAlive() {
        #expect(Date.calculateStreak(from: [daysAgo(1)]) == 1)
    }

    @Test func twoDayGapBreaksStreak() {
        #expect(Date.calculateStreak(from: [daysAgo(2)]) == 0)
    }

    @Test func consecutiveDaysAccumulate() {
        let dates = [Self.today, daysAgo(1), daysAgo(2), daysAgo(3)]
        #expect(Date.calculateStreak(from: dates) == 4)
    }

    @Test func gapInMiddleStopsCount() {
        // today, yesterday, then a hole at -2, then -3: streak is 2.
        let dates = [Self.today, daysAgo(1), daysAgo(3)]
        #expect(Date.calculateStreak(from: dates) == 2)
    }

    @Test func multipleSessionsSameDayCountOnce() {
        let dates = [Self.today, Self.today, Self.today, daysAgo(1)]
        #expect(Date.calculateStreak(from: dates) == 2)
    }
}

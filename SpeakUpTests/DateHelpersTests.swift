import Testing
import Foundation
@testable import SpeakUp


struct StreakCalculationTests {
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
        let dates = [Self.today, daysAgo(1), daysAgo(3)]
        #expect(Date.calculateStreak(from: dates) == 2)
    }

    @Test func multipleSessionsSameDayCountOnce() {
        let dates = [Self.today, Self.today, Self.today, daysAgo(1)]
        #expect(Date.calculateStreak(from: dates) == 2)
    }
}

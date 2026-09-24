import Foundation
import Testing
@testable import SpeakUp

struct HistoryWeekTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: "\(string)T12:00:00Z")!
    }

    private func take(_ date: String, score: Int?) -> RecordingSummary {
        RecordingSummary(
            id: UUID(), date: day(date), actualDuration: 60, displayTitle: date,
            isFavorite: false, isProcessing: false, storyId: nil, promptCategory: nil,
            overallScore: score, wpm: nil, fillerCount: nil, searchableText: date
        )
    }

    @Test("Takes bucket by calendar week, newest week first, order kept inside a week")
    func groups() {
        let takes = [
            take("2026-09-23", score: 80), // Wed
            take("2026-09-21", score: 70), // Mon, same week
            take("2026-09-20", score: 60), // Sun, previous week
            take("2026-08-03", score: nil),
        ]
        let weeks = HistoryWeek.group(takes, calendar: calendar)

        #expect(weeks.map(\.summaries.count) == [2, 1, 1])
        #expect(weeks[0].summaries.map(\.displayTitle) == ["2026-09-23", "2026-09-21"])
        #expect(weeks[0].start == day("2026-09-21").addingTimeInterval(-12 * 3600))
    }

    @Test("Titles read relative for the last two weeks, then as a range")
    func titles() {
        let now = day("2026-09-23")
        let weeks = HistoryWeek.group(
            [take("2026-09-22", score: 1), take("2026-09-15", score: 1), take("2026-09-08", score: 1), take("2025-12-30", score: 1)],
            calendar: calendar
        )

        #expect(weeks[0].title(now: now, calendar: calendar) == "This week")
        #expect(weeks[1].title(now: now, calendar: calendar) == "Last week")
        #expect(weeks[2].title(now: now, calendar: calendar).contains("Sep"))
        #expect(weeks[3].title(now: now, calendar: calendar).contains("2025"))
    }

    @Test("Caption averages scored takes only")
    func caption() {
        let week = HistoryWeek(start: .now, summaries: [take("2026-09-22", score: 80), take("2026-09-22", score: 71), take("2026-09-22", score: nil)])
        #expect(week.caption == "3 takes · avg 75")
        #expect(HistoryWeek(start: .now, summaries: [take("2026-09-22", score: nil)]).caption == "1 take")
    }
}

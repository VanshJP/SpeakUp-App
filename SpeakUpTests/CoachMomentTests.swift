import Testing
import Foundation
@testable import SpeakUp

// Coach notes are pure policy over a snapshot — no SwiftData, injected clock.
// What matters: signals fire for the right facts, celebrations spend the
// weekly budget, and care notes (welcome-back / soft landing) never do.

private let day: TimeInterval = 24 * 60 * 60
private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

private func snap(
    now: Date = t0,
    streak: Int = 0,
    practicedToday: Bool = false,
    daysSince: Int? = nil,
    firstPractice: Date? = nil,
    overall: Int? = nil,
    fillers: Int? = nil,
    words: Int? = nil,
    newlyCleared: [CoachDimension] = [],
    name: String = ""
) -> CoachMomentSnapshot {
    CoachMomentSnapshot(
        now: now,
        currentStreak: streak,
        practicedToday: practicedToday,
        daysSinceLastPractice: daysSince,
        firstPracticeDate: firstPractice,
        latestOverall: overall,
        latestFillerCount: fillers,
        latestTotalWords: words,
        newlyClearedDimensions: newlyCleared,
        userName: name
    )
}

private func emptyBudget(at now: Date = t0) -> CoachMomentBudget {
    CoachMomentBudget(
        weekKey: CoachMomentEngine.weekKey(for: now),
        celebrationsUsed: 0,
        deliveredIDs: []
    )
}

// MARK: - Detection

struct CoachMomentSignalTests {
    @Test func lapseNeedsFiveQuietDays() {
        let tooSoon = CoachMomentEngine.detectSignals(snap(daysSince: 4))
        #expect(!tooSoon.contains(.returnFromLapse))

        let ready = CoachMomentEngine.detectSignals(snap(daysSince: 5))
        #expect(ready.contains(.returnFromLapse))
    }

    @Test func lapseDoesNotFireOnAPracticeDay() {
        let signals = CoachMomentEngine.detectSignals(
            snap(practicedToday: true, daysSince: 8)
        )
        #expect(!signals.contains(.returnFromLapse))
    }

    @Test func welcomeBackCopyDoesNotCountDays() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(daysSince: 8, name: "Ada"),
            budget: emptyBudget(),
            surface: .today
        )
        #expect(moment?.signal == .returnFromLapse)
        #expect(moment?.body.contains("day") == false)
        #expect(moment?.body.contains("8") == false)
    }

    @Test func streakMilestoneIsEverySeventhPracticedDay() {
        #expect(
            CoachMomentEngine.detectSignals(
                snap(streak: 7, practicedToday: true)
            ).contains(.streakMilestone)
        )
        #expect(
            !CoachMomentEngine.detectSignals(
                snap(streak: 8, practicedToday: true)
            ).contains(.streakMilestone)
        )
        #expect(
            !CoachMomentEngine.detectSignals(
                snap(streak: 7, practicedToday: false)
            ).contains(.streakMilestone)
        )
    }

    @Test func softLandingNeedsARealButRoughTake() {
        #expect(
            CoachMomentEngine.detectSignals(
                snap(overall: 30, words: 80)
            ).contains(.softLanding)
        )
        #expect(
            !CoachMomentEngine.detectSignals(
                snap(overall: 0, words: 0)
            ).contains(.softLanding)
        )
        #expect(
            !CoachMomentEngine.detectSignals(
                snap(overall: 70, words: 80)
            ).contains(.softLanding)
        )
    }

    @Test func fillerBreakthroughNeedsEnoughWords() {
        #expect(
            CoachMomentEngine.detectSignals(
                snap(fillers: 0, words: 40)
            ).contains(.fillerBreakthrough)
        )
        #expect(
            !CoachMomentEngine.detectSignals(
                snap(fillers: 0, words: 10)
            ).contains(.fillerBreakthrough)
        )
    }

    @Test func anniversaryHitsKnownMilestones() {
        let first = t0.addingTimeInterval(-30 * day)
        #expect(
            CoachMomentEngine.detectSignals(
                snap(now: t0, firstPractice: first)
            ).contains(.practiceAnniversary)
        )
        let notYet = t0.addingTimeInterval(-29 * day)
        #expect(
            !CoachMomentEngine.detectSignals(
                snap(now: t0, firstPractice: notYet)
            ).contains(.practiceAnniversary)
        )
    }
}

// MARK: - Budget / propose

struct CoachMomentBudgetTests {
    @Test func careNotesDoNotSpendTheCelebrationBudget() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(daysSince: 6, name: "Ada"),
            budget: emptyBudget()
        )
        #expect(moment?.signal == .returnFromLapse)
        #expect(moment?.isCelebration == false)
        #expect(moment?.surface == .today)
    }

    @Test func celebrationsRequireRemainingBudget() {
        var spent = emptyBudget()
        spent.celebrationsUsed = CoachMomentBudget.weeklyCelebrationCap

        let blocked = CoachMomentEngine.propose(
            snapshot: snap(
                streak: 7,
                practicedToday: true,
                overall: 90,
                fillers: 0,
                words: 100
            ),
            budget: spent
        )
        #expect(blocked == nil || blocked?.isCelebration == false)
        #expect(blocked?.signal != .streakMilestone)
        #expect(blocked?.signal != .fillerBreakthrough)
    }

    @Test func softLandingBeatsOtherDetailCelebrationsOnPriority() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(
                streak: 7,
                practicedToday: true,
                overall: 30,
                fillers: 0,
                words: 80
            ),
            budget: emptyBudget(),
            surface: .detail
        )
        #expect(moment?.signal == .softLanding)
        #expect(moment?.surface == .detail)
    }

    @Test func overlaySurfaceIgnoresTodayCare() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(
                streak: 14,
                practicedToday: true,
                daysSince: 6
            ),
            budget: emptyBudget(),
            surface: .overlay
        )
        #expect(moment?.signal == .streakMilestone)
        #expect(moment?.surface == .overlay)
    }

    @Test func deliveredIdsAreNotReProposed() {
        let snapshot = snap(daysSince: 6)
        guard let first = CoachMomentEngine.propose(snapshot: snapshot, budget: emptyBudget()) else {
            Issue.record("expected a welcome-back note")
            return
        }
        var budget = emptyBudget()
        budget.deliveredIDs = [first.id]
        #expect(CoachMomentEngine.propose(snapshot: snapshot, budget: budget) == nil)
    }

    @Test func weekRollResetsCelebrationCount() {
        let oldKey = CoachMomentEngine.weekKey(for: t0.addingTimeInterval(-14 * day))
        let stale = CoachMomentBudget(weekKey: oldKey, celebrationsUsed: 1, deliveredIDs: ["x"])
        let rolled = stale.rolling(now: t0)
        #expect(rolled.celebrationsUsed == 0)
        #expect(rolled.weekKey == CoachMomentEngine.weekKey(for: t0))
        #expect(rolled.deliveredIDs == ["x"])
    }

    @Test func cappedDeliveredIdsStayBounded() {
        let ids = (0..<50).map { "id-\($0)" }
        let next = CoachMomentEngine.cappedDeliveredIDs(ids, adding: "fresh", limit: 40)
        #expect(next.count == 40)
        #expect(next.last == "fresh")
        #expect(!next.contains("id-0"))
    }
}

// MARK: - Axis clear

struct CoachMomentAxisClearTests {
    @Test func newlyClearedIgnoresAlreadyMarkedDimensions() {
        let scores = SpeechSubscores(
            clarity: 90,
            pace: 70,
            fillerUsage: 91,
            pauseQuality: 70
        )
        let fresh = CoachMomentEngine.newlyCleared(
            current: scores,
            previouslyCleared: []
        )
        #expect(fresh.contains(.clarity))
        #expect(fresh.contains(.fillers))

        let again = CoachMomentEngine.newlyCleared(
            current: scores,
            previouslyCleared: ["clarity", "fillers"]
        )
        #expect(again.isEmpty)
    }
}

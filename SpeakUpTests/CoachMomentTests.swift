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
    practicedToday: Bool = false,
    daysSince: Int? = nil,
    lastPractice: Date? = t0,
    firstPractice: Date? = nil,
    scoredSessions: Int = 2,
    overall: Int? = nil,
    words: Int? = nil,
    newlyCleared: [CoachDimension] = [],
    name: String = ""
) -> CoachMomentSnapshot {
    CoachMomentSnapshot(
        now: now,
        practicedToday: practicedToday,
        daysSinceLastPractice: daysSince,
        lastPracticeDate: lastPractice,
        firstPracticeDate: firstPractice,
        scoredSessionCount: scoredSessions,
        latestOverall: overall,
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
        // Absences are not narrated as a tally — "today's prompt" is fine.
        #expect(moment?.body.contains("8") == false)
        #expect(moment?.body.localizedCaseInsensitiveContains("days") == false)
        #expect(moment?.body.localizedCaseInsensitiveContains("been") == false)
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

    @Test func firstScoredTakeGetsNoDetailCoachNote() {
        let signals = CoachMomentEngine.detectSignals(
            snap(
                scoredSessions: 1,
                overall: 30,
                words: 80,
                newlyCleared: [.clarity]
            )
        )
        #expect(!signals.contains(.softLanding))
        #expect(!signals.contains(.firstAxisClear))
    }

    @Test func anniversaryHitsKnownMilestones() {
        let first = t0.addingTimeInterval(-30 * day)
        #expect(
            CoachMomentEngine.detectSignals(
                snap(now: t0, firstPractice: first)
            ).contains(.practiceAnniversary)
        )
        let moment = CoachMomentEngine.propose(
            snapshot: snap(now: t0, firstPractice: first),
            budget: emptyBudget(),
            surface: .overlay
        )
        #expect(moment?.action == .close)
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
                firstPractice: t0.addingTimeInterval(-30 * day)
            ),
            budget: spent
        )
        #expect(blocked == nil)
    }

    @Test func softLandingBeatsOtherDetailCelebrationsOnPriority() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(
                overall: 30,
                words: 80,
                newlyCleared: [.clarity]
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
                daysSince: 6,
                firstPractice: t0.addingTimeInterval(-30 * day)
            ),
            budget: emptyBudget(),
            surface: .overlay
        )
        #expect(moment?.signal == .practiceAnniversary)
        #expect(moment?.surface == .overlay)
    }

    @Test func welcomeBackCareBeatsAnAnniversaryCelebration() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(
                daysSince: 6,
                firstPractice: t0.addingTimeInterval(-30 * day)
            ),
            budget: emptyBudget()
        )
        #expect(moment?.signal == .returnFromLapse)
        #expect(moment?.surface == .today)
    }

    @Test func softLandingCareBeatsAnAnniversaryCelebration() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(
                firstPractice: t0.addingTimeInterval(-30 * day),
                overall: 30,
                words: 80
            ),
            budget: emptyBudget()
        )
        #expect(moment?.signal == .softLanding)
        #expect(moment?.surface == .detail)
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

    @Test func welcomeBackIsOncePerAbsenceEpisode() {
        let lastPractice = t0.addingTimeInterval(-10 * day)
        let firstDay = snap(
            now: t0,
            daysSince: 10,
            lastPractice: lastPractice
        )
        guard let first = CoachMomentEngine.propose(
            snapshot: firstDay,
            budget: emptyBudget()
        ) else {
            Issue.record("expected a welcome-back note")
            return
        }

        var delivered = emptyBudget(at: t0.addingTimeInterval(day))
        delivered.deliveredIDs = [first.id]
        let nextDay = snap(
            now: t0.addingTimeInterval(day),
            daysSince: 11,
            lastPractice: lastPractice
        )
        #expect(
            CoachMomentEngine.propose(snapshot: nextDay, budget: delivered) == nil
        )
        #expect(first.id.hasPrefix("return-since-"))
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

    @Test func capPreservesMilestonesAndCurrentReturnEpisode() {
        let ids = [
            "anniversary-30",
            "axis-clarity",
            "return-since-2026-01-01"
        ]
            + (0..<50).map { "soft-\($0)" }
        let next = CoachMomentEngine.cappedDeliveredIDs(
            ids,
            adding: "fresh",
            limit: 40
        )
        #expect(next.contains("anniversary-30"))
        #expect(next.contains("axis-clarity"))
        #expect(next.contains("return-since-2026-01-01"))
        #expect(next.count == 43)
    }

    @Test func oldReturnEpisodesAreBounded() {
        let ids = (0..<12).map { "return-since-\($0)" }
        let next = CoachMomentEngine.cappedDeliveredIDs(
            ids,
            adding: "fresh",
            limit: 40
        )
        #expect(!next.contains("return-since-0"))
        #expect(!next.contains("return-since-1"))
        #expect(next.contains("return-since-11"))
        #expect(next.count == 11)
    }

    @Test func seeingACelebrationSpendsTheWeeklySlotEvenWhenDismissed() {
        let budget = emptyBudget()
        guard let celebration = CoachMomentEngine.propose(
            snapshot: snap(firstPractice: t0.addingTimeInterval(-30 * day)),
            budget: budget,
            surface: .overlay
        ) else {
            Issue.record("expected an anniversary celebration")
            return
        }

        // Both accept and dismiss call this same pure transition.
        let spent = budget.recordingDelivery(of: celebration, now: t0)
        #expect(spent.celebrationsUsed == CoachMomentBudget.weeklyCelebrationCap)
        #expect(spent.deliveredIDs.contains(celebration.id))

        let second = CoachMomentEngine.propose(
            snapshot: snap(newlyCleared: [.clarity]),
            budget: spent,
            surface: .detail
        )
        #expect(second == nil)
    }

    @Test func recordingTheSameDeliveryTwiceDoesNotDoubleSpend() {
        let budget = emptyBudget()
        guard let celebration = CoachMomentEngine.propose(
            snapshot: snap(firstPractice: t0.addingTimeInterval(-30 * day)),
            budget: budget,
            surface: .overlay
        ) else {
            Issue.record("expected an anniversary celebration")
            return
        }

        let once = budget.recordingDelivery(of: celebration, now: t0)
        let twice = once.recordingDelivery(of: celebration, now: t0)
        #expect(twice.celebrationsUsed == 1)
        #expect(twice.deliveredIDs.filter { $0 == celebration.id }.count == 1)
    }
}

// MARK: - Axis clear

struct CoachMomentAxisClearTests {
    @Test func clearedAxisProposesOneFactualDetailNote() {
        let moment = CoachMomentEngine.propose(
            snapshot: snap(newlyCleared: [.clarity]),
            budget: emptyBudget(),
            surface: .detail
        )
        #expect(moment?.signal == .firstAxisClear)
        #expect(moment?.title == "Clarity reached target")
        #expect(moment?.body.localizedCaseInsensitiveContains("first") == false)
    }

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

import Testing
import Foundation
@testable import SpeakUp

// Hospitality is pure policy over a snapshot — no SwiftData, injected clock.
// What matters: ghosts fire for the right facts, legends spend the weekly
// budget, and care gestures (soft return / dignity) never do.

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
    transcript: String? = nil,
    newlyCleared: [CoachDimension] = [],
    name: String = "",
    life: HospitalityLifeContext? = nil
) -> HospitalitySnapshot {
    HospitalitySnapshot(
        now: now,
        currentStreak: streak,
        practicedToday: practicedToday,
        daysSinceLastPractice: daysSince,
        firstPracticeDate: firstPractice,
        latestOverall: overall,
        latestFillerCount: fillers,
        latestTotalWords: words,
        latestTranscript: transcript,
        newlyClearedDimensions: newlyCleared,
        userName: name,
        lifeContext: life
    )
}

private func emptyBudget(at now: Date = t0) -> HospitalityBudgetState {
    HospitalityBudgetState(
        weekKey: HospitalityEngine.weekKey(for: now),
        legendsUsed: 0,
        deliveredIDs: []
    )
}

// MARK: - Detection

struct HospitalitySignalTests {
    @Test func lapseNeedsThreeQuietDays() {
        let tooSoon = HospitalityEngine.detectSignals(snap(daysSince: 2))
        #expect(!tooSoon.contains(.returnFromLapse))

        let ready = HospitalityEngine.detectSignals(snap(daysSince: 3))
        #expect(ready.contains(.returnFromLapse))
    }

    @Test func lapseDoesNotFireOnAPracticeDay() {
        let signals = HospitalityEngine.detectSignals(
            snap(practicedToday: true, daysSince: 5)
        )
        #expect(!signals.contains(.returnFromLapse))
    }

    @Test func streakMilestoneIsEverySeventhPracticedDay() {
        #expect(
            HospitalityEngine.detectSignals(
                snap(streak: 7, practicedToday: true)
            ).contains(.streakMilestone)
        )
        #expect(
            !HospitalityEngine.detectSignals(
                snap(streak: 8, practicedToday: true)
            ).contains(.streakMilestone)
        )
        #expect(
            !HospitalityEngine.detectSignals(
                snap(streak: 7, practicedToday: false)
            ).contains(.streakMilestone)
        )
    }

    @Test func softLandingNeedsARealButRoughTake() {
        #expect(
            HospitalityEngine.detectSignals(
                snap(overall: 30, words: 80)
            ).contains(.softLanding)
        )
        // Dead mic (overall 0) is a capture failure, not a rough take.
        #expect(
            !HospitalityEngine.detectSignals(
                snap(overall: 0, words: 0)
            ).contains(.softLanding)
        )
        #expect(
            !HospitalityEngine.detectSignals(
                snap(overall: 70, words: 80)
            ).contains(.softLanding)
        )
    }

    @Test func fillerBreakthroughNeedsEnoughWords() {
        #expect(
            HospitalityEngine.detectSignals(
                snap(fillers: 0, words: 40)
            ).contains(.fillerBreakthrough)
        )
        #expect(
            !HospitalityEngine.detectSignals(
                snap(fillers: 0, words: 10)
            ).contains(.fillerBreakthrough)
        )
        #expect(
            !HospitalityEngine.detectSignals(
                snap(fillers: 2, words: 80)
            ).contains(.fillerBreakthrough)
        )
    }

    @Test func anniversaryHitsKnownMilestones() {
        let first = t0.addingTimeInterval(-30 * day)
        #expect(
            HospitalityEngine.detectSignals(
                snap(now: t0, firstPractice: first)
            ).contains(.practiceAnniversary)
        )
        let notYet = t0.addingTimeInterval(-29 * day)
        #expect(
            !HospitalityEngine.detectSignals(
                snap(now: t0, firstPractice: notYet)
            ).contains(.practiceAnniversary)
        )
    }

    @Test func lifeContextReadsTranscriptGhosts() {
        #expect(
            HospitalityLifeContext.detect(in: "I have a job interview tomorrow")
            == .interview
        )
        #expect(
            HospitalityLifeContext.detect(in: "pitching baseball tonight")
            == nil
        )
        #expect(
            HospitalityEngine.detectSignals(
                snap(transcript: "Need to prep my pitch deck for investors")
            ).contains(.lifeContextPrep)
        )
    }
}

// MARK: - Budget / propose

struct HospitalityBudgetTests {
    @Test func careGesturesDoNotSpendTheLegendBudget() {
        let moment = HospitalityEngine.propose(
            snapshot: snap(daysSince: 5, name: "Ada"),
            budget: emptyBudget()
        )
        #expect(moment?.signal == .returnFromLapse)
        #expect(moment?.isLegend == false)
        #expect(moment?.surface == .today)
    }

    @Test func legendsRequireRemainingBudget() {
        var spent = emptyBudget()
        spent.legendsUsed = HospitalityBudgetState.weeklyLegendCap

        let blocked = HospitalityEngine.propose(
            snapshot: snap(
                streak: 7,
                practicedToday: true,
                overall: 90,
                fillers: 0,
                words: 100
            ),
            budget: spent
        )
        // Soft landing is care (not a legend) but overall 90 won't fire it.
        // With budget spent, streak / filler legends must not ship.
        #expect(blocked == nil || blocked?.isLegend == false)
        #expect(blocked?.signal != .streakMilestone)
        #expect(blocked?.signal != .fillerBreakthrough)
    }

    @Test func softLandingBeatsOtherDetailLegendsOnPriority() {
        let moment = HospitalityEngine.propose(
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
        let moment = HospitalityEngine.propose(
            snapshot: snap(
                streak: 14,
                practicedToday: true,
                daysSince: 5
            ),
            budget: emptyBudget(),
            surface: .overlay
        )
        #expect(moment?.signal == .streakMilestone)
        #expect(moment?.surface == .overlay)
    }

    @Test func deliveredIdsAreNotReProposed() {
        let snapshot = snap(daysSince: 4)
        guard let first = HospitalityEngine.propose(snapshot: snapshot, budget: emptyBudget()) else {
            Issue.record("expected a return-from-lapse moment")
            return
        }
        var budget = emptyBudget()
        budget.deliveredIDs = [first.id]
        #expect(HospitalityEngine.propose(snapshot: snapshot, budget: budget) == nil)
    }

    @Test func weekRollResetsLegendCount() {
        let oldKey = HospitalityEngine.weekKey(for: t0.addingTimeInterval(-14 * day))
        let stale = HospitalityBudgetState(weekKey: oldKey, legendsUsed: 1, deliveredIDs: ["x"])
        let rolled = stale.rolling(now: t0)
        #expect(rolled.legendsUsed == 0)
        #expect(rolled.weekKey == HospitalityEngine.weekKey(for: t0))
        #expect(rolled.deliveredIDs == ["x"])
    }

    @Test func cappedDeliveredIdsStayBounded() {
        let ids = (0..<50).map { "id-\($0)" }
        let next = HospitalityEngine.cappedDeliveredIDs(ids, adding: "fresh", limit: 40)
        #expect(next.count == 40)
        #expect(next.last == "fresh")
        #expect(!next.contains("id-0"))
    }
}

// MARK: - Axis clear

struct HospitalityAxisClearTests {
    @Test func newlyClearedIgnoresAlreadyMarkedDimensions() {
        let scores = SpeechSubscores(
            clarity: 90,
            pace: 70,
            fillerUsage: 91,
            pauseQuality: 70
        )
        let fresh = HospitalityEngine.newlyCleared(
            current: scores,
            previouslyCleared: []
        )
        #expect(fresh.contains(.clarity))
        #expect(fresh.contains(.fillers))

        let again = HospitalityEngine.newlyCleared(
            current: scores,
            previouslyCleared: ["clarity", "fillers"]
        )
        #expect(again.isEmpty)
    }
}

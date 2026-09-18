import Testing
import Foundation
@testable import SpeakUp

// MARK: - Streak freeze

struct StreakProtectionTests {
    private static let today = Calendar.current.startOfDay(for: Date())

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Self.today)!
    }

    /// 5 practice days earns exactly one freeze.
    @Test func freezesAccrueEveryFiveDays() {
        #expect(StreakProtection.freezesAvailable(practiceDayCount: 4, frozenDayCount: 0) == 0)
        #expect(StreakProtection.freezesAvailable(practiceDayCount: 5, frozenDayCount: 0) == 1)
        #expect(StreakProtection.freezesAvailable(practiceDayCount: 10, frozenDayCount: 0) == 2)
    }

    @Test func freezeBalanceIsCapped() {
        #expect(StreakProtection.freezesAvailable(practiceDayCount: 500, frozenDayCount: 0)
            == StreakProtection.maxBankedFreezes)
    }

    @Test func spentFreezesReduceBalance() {
        #expect(StreakProtection.freezesAvailable(practiceDayCount: 10, frozenDayCount: 1) == 1)
        #expect(StreakProtection.freezesAvailable(practiceDayCount: 10, frozenDayCount: 2) == 0)
        // Never negative, even if history is edited out from under it.
        #expect(StreakProtection.freezesAvailable(practiceDayCount: 1, frozenDayCount: 9) == 0)
    }

    @Test func liveStreakSpendsNothing() {
        let days = (0...6).map { daysAgo($0) }
        let result = StreakProtection.resolve(practiceDays: days, frozenDays: [])
        #expect(!result.didConsumeFreeze)
        #expect(result.frozenDays.isEmpty)
    }

    /// The core case: missed yesterday, freeze banked, streak survives.
    @Test func missedYesterdayConsumesAFreeze() {
        let days = (2...8).map { daysAgo($0) }  // 7 practice days, none yesterday
        let result = StreakProtection.resolve(practiceDays: days, frozenDays: [])

        #expect(result.didConsumeFreeze)
        #expect(result.consumedDay == daysAgo(1))
        #expect(result.rescuedStreak == 7)
        #expect(result.freezesRemaining == 0)
    }

    @Test func noFreezeBankedMeansNoRescue() {
        // Only 3 practice days - under the 5 needed to earn one.
        let days = (2...4).map { daysAgo($0) }
        let result = StreakProtection.resolve(practiceDays: days, frozenDays: [])
        #expect(!result.didConsumeFreeze)
    }

    /// A freeze protects a slip, not an absence - two days gone is a comeback.
    @Test func twoDayAbsenceIsNotRescued() {
        let days = (3...9).map { daysAgo($0) }
        let result = StreakProtection.resolve(practiceDays: days, frozenDays: [])
        #expect(!result.didConsumeFreeze)
    }

    /// Never burn a freeze when there is no chain for it to hold together.
    @Test func noLiveStreakSpendsNothing() {
        let days = (10...20).map { daysAgo($0) }
        let result = StreakProtection.resolve(practiceDays: days, frozenDays: [])
        #expect(!result.didConsumeFreeze)
    }

    @Test func alreadyFrozenDayIsNotChargedTwice() {
        let days = (2...8).map { daysAgo($0) }
        let once = StreakProtection.resolve(practiceDays: days, frozenDays: [])
        let twice = StreakProtection.resolve(practiceDays: days, frozenDays: once.frozenDays)

        #expect(once.didConsumeFreeze)
        #expect(!twice.didConsumeFreeze)
        #expect(twice.frozenDays.count == once.frozenDays.count)
    }
}

// MARK: - Streak counting with freezes

struct FrozenStreakCalculationTests {
    private static let today = Calendar.current.startOfDay(for: Date())

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Self.today)!
    }

    @Test func frozenDayBridgesTheGap() {
        let practice = [daysAgo(0), daysAgo(1), daysAgo(3), daysAgo(4)]
        #expect(Date.calculateStreak(from: practice) == 2)
        #expect(Date.calculateStreak(from: practice, frozenDays: [daysAgo(2)]) == 4)
    }

    /// A freeze holds the chain but must never inflate the number - the streak
    /// stays a count of days the user actually spoke.
    @Test func frozenDayDoesNotCountAsPractice() {
        let practice = [daysAgo(1), daysAgo(3)]
        #expect(Date.calculateStreak(from: practice, frozenDays: [daysAgo(2)]) == 2)
    }

    @Test func frozenYesterdayKeepsStreakAlive() {
        let practice = [daysAgo(2), daysAgo(3)]
        #expect(Date.calculateStreak(from: practice) == 0)
        #expect(Date.calculateStreak(from: practice, frozenDays: [daysAgo(1)]) == 2)
    }

    @Test func freezeCannotResurrectADeadStreak() {
        let practice = [daysAgo(5), daysAgo(6)]
        #expect(Date.calculateStreak(from: practice, frozenDays: [daysAgo(1)]) == 0)
    }

    @Test func emptyFrozenDaysMatchesLegacyBehaviour() {
        let practice = [daysAgo(0), daysAgo(1), daysAgo(2)]
        #expect(Date.calculateStreak(from: practice, frozenDays: []) == 3)
    }
}

// MARK: - Notification ladder

struct RetentionNotificationPlannerTests {
    private func snapshot(
        streak: Int = 0,
        longest: Int = 0,
        lastPractice: Date? = nil,
        freezes: Int = 0,
        daily: Bool = true,
        streaks: Bool = true,
        comeback: Bool = true
    ) -> RetentionSnapshot {
        RetentionSnapshot(
            currentStreak: streak,
            longestStreak: longest,
            lastPracticeDate: lastPractice,
            freezesAvailable: freezes,
            dailyReminderEnabled: daily,
            streakRemindersEnabled: streaks,
            comebackRemindersEnabled: comeback
        )
    }

    private func ids(_ plan: [PlannedNotification]) -> Set<String> {
        Set(plan.map(\.id))
    }

    /// The consent contract: reminders off means nothing is scheduled at all.
    @Test func reminderToggleOffSchedulesNothing() {
        let plan = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 30, lastPractice: Date().adding(days: -1), daily: false,
                          streaks: false, comeback: false)
        )
        #expect(plan.isEmpty)
    }

    @Test func dailyReminderIsAlwaysScheduledWhenEnabled() {
        let plan = RetentionNotificationPlanner.plan(for: snapshot())
        #expect(ids(plan).contains(RetentionNotificationPlanner.dailyReminderID))
    }

    @Test func streakAtRiskOnlyWhenAStreakIsLive() {
        let none = RetentionNotificationPlanner.plan(for: snapshot(streak: 0))
        #expect(!ids(none).contains(RetentionNotificationPlanner.streakAtRiskID))

        let live = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 3, lastPractice: Date().adding(days: -1))
        )
        #expect(ids(live).contains(RetentionNotificationPlanner.streakAtRiskID))
    }

    /// Practising clears the rescue - nobody gets told their streak is ending
    /// on a day they already saved it.
    @Test func practicingTodayCancelsTheRescue() {
        let plan = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 9, lastPractice: Date())
        )
        #expect(!ids(plan).contains(RetentionNotificationPlanner.streakAtRiskID))
        #expect(!ids(plan).contains(RetentionNotificationPlanner.streakLastCallID))
    }

    @Test func lastCallIsReservedForLongStreaks() {
        let short = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 3, lastPractice: Date().adding(days: -1))
        )
        #expect(!ids(short).contains(RetentionNotificationPlanner.streakLastCallID))

        let long = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 12, lastPractice: Date().adding(days: -1))
        )
        #expect(ids(long).contains(RetentionNotificationPlanner.streakLastCallID))
    }

    /// The volume cap. Three is the ceiling, and only for a long streak at risk.
    @Test func neverMoreThanThreeInADay() {
        let worstCase = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 99, longest: 99, lastPractice: Date().adding(days: -1), freezes: 2)
        )
        let sameDay = worstCase.filter {
            switch $0.schedule {
            case .daily, .onceAt: return true
            case .afterDays: return false
            }
        }
        #expect(sameDay.count <= 3)
    }

    @Test func comebackLadderNeedsAPriorTake() {
        let never = RetentionNotificationPlanner.plan(for: snapshot(lastPractice: nil))
        #expect(ids(never).isDisjoint(with: Set(RetentionNotificationPlanner.comebackIDs)))

        let lapsed = RetentionNotificationPlanner.plan(
            for: snapshot(longest: 12, lastPractice: Date().adding(days: -1))
        )
        #expect(Set(RetentionNotificationPlanner.comebackIDs).isSubset(of: ids(lapsed)))
    }

    /// The ladder stops. Day 7 is the last rung - past that it is noise, and
    /// noise gets the app muted for good.
    @Test func comebackLadderStopsAtDaySeven() {
        let plan = RetentionNotificationPlanner.comebackLadder(
            for: snapshot(lastPractice: Date().adding(days: -1))
        )
        let offsets = plan.compactMap { planned -> Int? in
            if case let .afterDays(days) = planned.schedule { return days }
            return nil
        }
        #expect(offsets == [2, 4, 7])
    }

    @Test func toggledOffClassesAreOmitted() {
        let plan = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 10, lastPractice: Date().adding(days: -1),
                          streaks: false, comeback: false)
        )
        #expect(ids(plan) == [RetentionNotificationPlanner.dailyReminderID])
    }

    // MARK: Copy

    /// The whole point of the rewrite: copy states what is at stake instead of
    /// handing the reader an excuse to skip.
    @Test func copyNamesTheStakeAndNeverHedges() {
        let snap = snapshot(streak: 14, longest: 14, lastPractice: Date().adding(days: -1), freezes: 1)
        let plan = RetentionNotificationPlanner.plan(for: snap)

        let atRisk = plan.first { $0.id == RetentionNotificationPlanner.streakAtRiskID }
        #expect(atRisk?.title.contains("14") == true)

        let hedges = ["if you want", "only if", "no pressure", "whenever you are ready", "skip today"]
        for notification in plan {
            let text = (notification.title + " " + notification.body).lowercased()
            for hedge in hedges {
                #expect(!text.contains(hedge), "hedging copy in \(notification.id): \(text)")
            }
        }
    }

    @Test func dailyReminderCopyTracksTheStreak() {
        #expect(RetentionNotificationPlanner.dailyReminder(for: snapshot(streak: 0))
            .title.contains("first take"))
        #expect(RetentionNotificationPlanner.dailyReminder(for: snapshot(streak: 21))
            .title.contains("21"))
    }

    @Test func rescueOutranksRoutine() {
        let plan = RetentionNotificationPlanner.plan(
            for: snapshot(streak: 5, lastPractice: Date().adding(days: -1))
        )
        let daily = plan.first { $0.id == RetentionNotificationPlanner.dailyReminderID }!
        let atRisk = plan.first { $0.id == RetentionNotificationPlanner.streakAtRiskID }!
        #expect(atRisk.relevance > daily.relevance)
    }

    @Test func milestonesFireOnlyOnListedDays() {
        #expect(RetentionNotificationPlanner.milestone(streak: 7) != nil)
        #expect(RetentionNotificationPlanner.milestone(streak: 30) != nil)
        #expect(RetentionNotificationPlanner.milestone(streak: 8) == nil)
        #expect(RetentionNotificationPlanner.milestone(streak: 0) == nil)
    }

    @Test func freezeUsedCopyReportsTheSaveAndTheBalance() {
        let spent = RetentionNotificationPlanner.freezeUsed(rescuedStreak: 22, freezesRemaining: 0)
        #expect(spent.title.contains("22"))
        #expect(spent.body.contains("last one"))

        let remaining = RetentionNotificationPlanner.freezeUsed(rescuedStreak: 22, freezesRemaining: 1)
        #expect(remaining.body.contains("1 left"))
    }
}

// MARK: - Snapshot helpers

struct RetentionSnapshotTests {
    @Test func daysSinceLastPracticeCountsWholeDays() {
        let snap = RetentionSnapshot(lastPracticeDate: Date().adding(days: -3))
        #expect(snap.daysSinceLastPractice() == 3)
    }

    @Test func daysSinceLastPracticeIsNilWithoutHistory() {
        #expect(RetentionSnapshot().daysSinceLastPractice() == nil)
    }

    @Test func practicedTodayTracksTheDayBoundary() {
        #expect(RetentionSnapshot(lastPracticeDate: Date()).practicedToday)
        #expect(!RetentionSnapshot(lastPracticeDate: Date().adding(days: -1)).practicedToday)
    }
}

import Foundation

// MARK: - Streak Protection

/// Streak freezes: the mechanic Duolingo's own retention team credits for the
/// step change in long-run retention. The lever is *forgiveness*, not pressure - 
/// one missed Tuesday resetting a 40-day habit to zero is what makes people quit
/// for good, because the thing they were protecting is already gone.
///
/// Pure math, no storage. `UserSettings.streakFrozenDays` is the only new
/// column; everything else is derived, so recomputing on every launch converges
/// instead of drifting.
nonisolated enum StreakProtection {
    /// Practice days needed to bank one freeze.
    static let daysPerEarnedFreeze = 5

    /// Hard cap on banked freezes. Duolingo caps free users at 2 deliberately:
    /// a freeze that never runs out stops meaning anything, and the streak
    /// stops being a record of having shown up.
    static let maxBankedFreezes = 2

    /// Freezes the user currently holds. Derived from lifetime practice days
    /// minus freezes already spent, so it is stable under recomputation.
    static func freezesAvailable(practiceDayCount: Int, frozenDayCount: Int) -> Int {
        let earned = practiceDayCount / daysPerEarnedFreeze
        return min(maxBankedFreezes, max(0, earned - frozenDayCount))
    }

    /// Live streak plus banked freezes, from practice timestamps and the days
    /// already covered by spent freezes.
    static func liveSnapshot(
        practiceDays: [Date],
        frozenDays: [Date],
        now: Date = Date()
    ) -> (currentStreak: Int, freezesAvailable: Int, frozenDays: [Date]) {
        let practice = Set(practiceDays.map(\.startOfDay))
        let frozen = Set(frozenDays.map(\.startOfDay)).subtracting(practice)
        let streak = Date.calculateStreak(
            from: practiceDays,
            frozenDays: frozen.map { $0 },
            now: now
        )
        let freezes = freezesAvailable(
            practiceDayCount: practice.count,
            frozenDayCount: frozen.count
        )
        return (streak, freezes, frozen.sorted(by: >))
    }

    /// The streak day a take just earned, or nil when it earned none because
    /// the day was already practised. Drives the score reveal's "Day N" beat,
    /// so it only fires on the take that actually moved the number.
    static func dayStarted(
        byTakeOn takeDate: Date,
        otherPracticeDays: [Date],
        frozenDays: [Date],
        now: Date = Date()
    ) -> Int? {
        let day = takeDate.startOfDay
        guard !otherPracticeDays.contains(where: { $0.startOfDay == day }) else { return nil }
        let streak = liveSnapshot(
            practiceDays: otherPracticeDays + [takeDate],
            frozenDays: frozenDays,
            now: now
        ).currentStreak
        return streak > 0 ? streak : nil
    }

    struct Resolution: Equatable {
        /// Frozen days after this pass, including any newly consumed one.
        var frozenDays: [Date]
        /// The day a freeze was just spent on, if one was.
        var consumedDay: Date?
        /// Freezes left after this pass.
        var freezesRemaining: Int
        /// The streak the freeze rescued. Zero when nothing was consumed.
        var rescuedStreak: Int

        var didConsumeFreeze: Bool { consumedDay != nil }
    }

    /// Spend a freeze on yesterday when the user missed it and had a live
    /// streak going in.
    ///
    /// Only ever covers a *single* day, matching Duolingo: a freeze protects a
    /// slip, not an absence. Two days gone is a comeback, which the comeback
    /// notification ladder handles instead.
    static func resolve(
        practiceDays: [Date],
        frozenDays: [Date],
        now: Date = Date()
    ) -> Resolution {
        let practice = Set(practiceDays.map(\.startOfDay))
        var frozen = Set(frozenDays.map(\.startOfDay)).subtracting(practice)
        let available = freezesAvailable(
            practiceDayCount: practice.count,
            frozenDayCount: frozen.count
        )
        let unchanged = Resolution(
            frozenDays: frozen.sorted(by: >),
            consumedDay: nil,
            freezesRemaining: available,
            rescuedStreak: 0
        )

        let today = now.startOfDay
        let yesterday = today.adding(days: -1)

        // Streak is alive on its own - nothing to rescue.
        guard !practice.contains(today), !practice.contains(yesterday) else {
            return unchanged
        }
        // Already covered, or nothing banked to spend.
        guard !frozen.contains(yesterday), available > 0 else { return unchanged }

        // Only rescue a streak that was actually running into yesterday. With
        // no live chain there is nothing for the freeze to hold together, and
        // spending one would quietly burn the user's balance for nothing.
        let dayBefore = yesterday.adding(days: -1)
        guard practice.contains(dayBefore) || frozen.contains(dayBefore) else {
            return unchanged
        }

        frozen.insert(yesterday)
        let rescued = Date.calculateStreak(
            from: practice.map { $0 },
            frozenDays: frozen.map { $0 },
            now: now
        )
        return Resolution(
            frozenDays: frozen.sorted(by: >),
            consumedDay: yesterday,
            freezesRemaining: freezesAvailable(
                practiceDayCount: practice.count,
                frozenDayCount: frozen.count
            ),
            rescuedStreak: rescued
        )
    }
}

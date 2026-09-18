import Foundation

// MARK: - Snapshot

/// Everything the planner needs to decide what to send. Pure value type so the
/// whole ladder is testable without `UNUserNotificationCenter`.
nonisolated struct RetentionSnapshot: Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var lastPracticeDate: Date?
    var freezesAvailable: Int
    var reminderHour: Int
    var reminderMinute: Int
    var dailyReminderEnabled: Bool
    var streakRemindersEnabled: Bool
    var comebackRemindersEnabled: Bool

    init(
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastPracticeDate: Date? = nil,
        freezesAvailable: Int = 0,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        dailyReminderEnabled: Bool = false,
        streakRemindersEnabled: Bool = true,
        comebackRemindersEnabled: Bool = true
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastPracticeDate = lastPracticeDate
        self.freezesAvailable = freezesAvailable
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.dailyReminderEnabled = dailyReminderEnabled
        self.streakRemindersEnabled = streakRemindersEnabled
        self.comebackRemindersEnabled = comebackRemindersEnabled
    }

    func practiced(on day: Date) -> Bool {
        guard let lastPracticeDate else { return false }
        return lastPracticeDate.startOfDay == day.startOfDay
    }

    var practicedToday: Bool { practiced(on: Date()) }

    /// Whole days since the last take. `nil` when the user has never practised.
    func daysSinceLastPractice(now: Date = Date()) -> Int? {
        guard let lastPracticeDate else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: lastPracticeDate.startOfDay,
            to: now.startOfDay
        ).day
        return days.map { max(0, $0) }
    }
}

// MARK: - Planned notification

nonisolated struct PlannedNotification: Equatable, Identifiable {
    enum Schedule: Equatable {
        /// Repeats every day at this wall-clock time.
        case daily(hour: Int, minute: Int)
        /// Fires once, at the next occurrence of this wall-clock time.
        case onceAt(hour: Int, minute: Int)
        /// Fires once, this many days from scheduling.
        case afterDays(Int)
    }

    var id: String
    var title: String
    var body: String
    var schedule: Schedule
    /// Drives ordering inside iOS's notification summary. Streak rescue
    /// outranks the routine nudge - it is the one with something at stake.
    var relevance: Double
    var badge: Int?
}

// MARK: - Planner

/// Builds the notification ladder.
///
/// Shaped by what Duolingo's retention team has published about their own
/// system, which is narrower than the folklore suggests:
///
/// 1. **Volume is capped, copy does the work.** Their team could tune timing,
///    template and copy freely but could not add notification *quantity*
///    without CEO sign-off. The wins came from relevance, not frequency.
///    This ladder sends at most three in a day, and only to someone with a
///    7-day-plus streak who has not practised - everyone else gets one or two.
/// 2. **Anchor to the user's own rhythm.** Their practice reminder lands ~23.5h
///    after the last session, which quietly converges on the time that person
///    actually practises rather than a time the product picked.
/// 3. **Name the stake.** A reminder that states the number on the line beats a
///    neutral one. Non-committal copy ("only if you want to") gives the reader
///    permission to skip, which is exactly what they do.
/// 4. **Stop nagging eventually.** The comeback ladder runs day 2, 4 and 7 and
///    then goes quiet. Past that it is noise, and noise gets the app muted - 
///    which costs the channel permanently.
nonisolated enum RetentionNotificationPlanner {
    // Identifiers, so scheduling and cancellation can never drift apart.
    static let dailyReminderID = "daily_reminder"
    static let streakAtRiskID = "streak_at_risk"
    static let streakLastCallID = "streak_last_call"
    static let comebackIDs = ["comeback_d2", "comeback_d4", "comeback_d7"]
    static let milestoneID = "streak_milestone"
    static let freezeUsedID = "streak_freeze_used"

    /// Every id this planner owns. Used to clear the slate before rescheduling.
    static var allManagedIDs: [String] {
        [dailyReminderID, streakAtRiskID, streakLastCallID] + comebackIDs
    }

    /// Evening rescue. Late enough to mean "today is nearly gone", early enough
    /// that a two-minute take is still realistic.
    static let atRiskHour = 20
    static let atRiskMinute = 30

    /// Last call, for streaks long enough that losing one genuinely stings.
    static let lastCallHour = 21
    static let lastCallMinute = 45
    static let lastCallMinimumStreak = 7

    /// Streak lengths worth interrupting someone to celebrate.
    static let milestones = [3, 7, 14, 30, 50, 100, 200, 365]

    // MARK: Plan

    static func plan(for snapshot: RetentionSnapshot) -> [PlannedNotification] {
        // The daily reminder toggle is the consent for the whole channel, not
        // just for one notification. With it off nothing ships, whatever the
        // sub-toggles say - enforced here as well as in `RetentionScheduler`,
        // so the contract cannot be bypassed by calling the planner directly.
        guard snapshot.dailyReminderEnabled else { return [] }

        var planned: [PlannedNotification] = [dailyReminder(for: snapshot)]

        // Streak rescue only exists if there is a streak to rescue and the day
        // is still unclaimed.
        if snapshot.streakRemindersEnabled,
           snapshot.currentStreak >= 1,
           !snapshot.practicedToday {
            planned.append(streakAtRisk(for: snapshot))
            if snapshot.currentStreak >= lastCallMinimumStreak {
                planned.append(streakLastCall(for: snapshot))
            }
        }

        if snapshot.comebackRemindersEnabled {
            planned.append(contentsOf: comebackLadder(for: snapshot))
        }

        return planned
    }

    // MARK: Daily reminder

    /// Rescheduled on every foreground, so the streak number in the copy is
    /// never more than one app-open stale.
    static func dailyReminder(for snapshot: RetentionSnapshot) -> PlannedNotification {
        let streak = snapshot.currentStreak
        let title: String
        let body: String

        switch streak {
        case 0:
            title = "Your first take is two minutes away"
            body = "Pick a prompt, talk until it feels done. That is the whole thing."
        case 1...2:
            title = "Day \(streak). Make it \(streak + 1)."
            body = "One take today keeps it going. Two minutes, then you are done."
        case 3..<lastCallMinimumStreak:
            // A 7-day streak is the documented inflection point for return
            // rates, so the copy counts down to it rather than to nothing.
            let remaining = lastCallMinimumStreak - streak
            title = "\(streak) days in a row"
            body = "\(remaining) more \(remaining == 1 ? "day" : "days") to a full week. One take today."
        default:
            title = "\(streak) days straight"
            body = "You have practised \(streak) days. Keep it that way - one take, right now."
        }

        return PlannedNotification(
            id: dailyReminderID,
            title: title,
            body: body,
            schedule: .daily(hour: snapshot.reminderHour, minute: snapshot.reminderMinute),
            relevance: 0.6,
            badge: 1
        )
    }

    // MARK: Streak rescue

    static func streakAtRisk(for snapshot: RetentionSnapshot) -> PlannedNotification {
        let streak = snapshot.currentStreak
        let body: String
        if snapshot.freezesAvailable > 0 {
            let freezes = snapshot.freezesAvailable
            body = "One take saves it. You have \(freezes) streak freeze\(freezes == 1 ? "" : "s") banked, but spending one costs you the day."
        } else {
            body = "One take saves it, and you have no freezes left. Two minutes is all it takes."
        }

        return PlannedNotification(
            id: streakAtRiskID,
            title: "Your \(streak)-day streak ends at midnight",
            body: body,
            schedule: .onceAt(hour: atRiskHour, minute: atRiskMinute),
            relevance: 1.0,
            badge: 1
        )
    }

    static func streakLastCall(for snapshot: RetentionSnapshot) -> PlannedNotification {
        PlannedNotification(
            id: streakLastCallID,
            title: "\(snapshot.currentStreak) days. About two hours left.",
            body: "Open Big Talk and talk for one minute. That is enough to keep it.",
            schedule: .onceAt(hour: lastCallHour, minute: lastCallMinute),
            relevance: 0.95,
            badge: 1
        )
    }

    // MARK: Comeback ladder

    /// Days 2, 4 and 7 after the last take, then silence. Each rung asks for
    /// less than the one before: the barrier to returning is the size of the
    /// thing being asked for, not the strength of the reminder.
    static func comebackLadder(for snapshot: RetentionSnapshot) -> [PlannedNotification] {
        guard snapshot.lastPracticeDate != nil else { return [] }

        let best = max(snapshot.longestStreak, snapshot.currentStreak)
        let bestLine = best >= 3
            ? "Your best run was \(best) days. Start the next one tonight."
            : "Start the next one tonight."

        return [
            PlannedNotification(
                id: comebackIDs[0],
                title: "You are one take from being back",
                body: bestLine,
                schedule: .afterDays(2),
                relevance: 0.8,
                badge: 1
            ),
            PlannedNotification(
                id: comebackIDs[1],
                title: "Four quiet days",
                body: "The hard part is opening the app, not the talking. One minute, any prompt.",
                schedule: .afterDays(4),
                relevance: 0.7,
                badge: 1
            ),
            PlannedNotification(
                id: comebackIDs[2],
                title: "Seven days out. Restart with one take.",
                body: "Pick any prompt and talk for sixty seconds. That is the whole ask.",
                schedule: .afterDays(7),
                relevance: 0.5,
                badge: nil
            )
        ]
    }

    // MARK: Immediate moments

    /// Fired the moment a streak crosses a milestone, while the feeling is
    /// attached to the thing that caused it.
    static func milestone(streak: Int) -> PlannedNotification? {
        guard milestones.contains(streak) else { return nil }
        let body: String
        switch streak {
        case 3: body = "Three days is where most people stop. You did not."
        case 7: body = "A full week. People who get here are far more likely to still be practising next month."
        case 14: body = "Two weeks. This is a habit now, not an experiment."
        case 30: body = "Thirty days of showing up. Your voice has changed more than you can hear yet."
        default: body = "\(streak) days of practice. That is rare, and it shows when you speak."
        }

        return PlannedNotification(
            id: milestoneID,
            title: "\(streak)-day streak",
            body: body,
            schedule: .afterDays(0),
            relevance: 0.9,
            badge: nil
        )
    }

    /// Sent when a freeze is spent, so the save is visible. A rescue the user
    /// never learns about buys no goodwill and teaches them nothing about the
    /// cost of the next miss.
    static func freezeUsed(rescuedStreak: Int, freezesRemaining: Int) -> PlannedNotification {
        let remainder = freezesRemaining == 0
            ? "That was your last one - today's take rebuilds your balance."
            : "\(freezesRemaining) left. Practise today to start earning another."

        return PlannedNotification(
            id: freezeUsedID,
            title: "Streak freeze used - your \(rescuedStreak)-day streak survived",
            body: "You missed yesterday, so a banked freeze covered it. \(remainder)",
            schedule: .afterDays(0),
            relevance: 0.85,
            badge: 1
        )
    }
}

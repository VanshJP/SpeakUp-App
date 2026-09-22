import Foundation
import SwiftData
import os.log

/// The one place that turns "where does this user stand" into a scheduled
/// notification ladder.
///
/// Every entry point - app foreground, finished take, settings change, first-run
/// setup - calls `refresh`. Keeping it single-entry is what stops the four call
/// sites from drifting into four slightly different ideas of the schedule, which
/// is how the previous build ended up with orphaned identifiers.
///
/// MainActor by default isolation, which is correct here: it reads and writes
/// the main `ModelContext`.
enum RetentionScheduler {
    private static let logger = Logger.app("Retention")

    /// Recompute streak protection and reschedule everything.
    ///
    /// - Parameters:
    /// - afterPractice: pass `true` straight after a take so the evening
    ///     rescue notifications are torn down immediately rather than at the
    ///     next foreground.
    /// - requestPermissionIfNeeded: pass `true` only where the user just
    ///     asked for reminders - that is the moment a system prompt is expected.
    ///     Background refreshes must never trigger it.
    @discardableResult
    static func refresh(
        context: ModelContext,
        service: NotificationService? = nil,
        afterPractice: Bool = false,
        requestPermissionIfNeeded: Bool = false
    ) async -> RetentionSnapshot? {
        let notifications = service ?? NotificationService()

        guard let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first else {
            return nil
        }

        let practiceDays = practiceDates(in: context)

        // MARK: Streak protection

        // Before any notification gate: a freeze is a promise about the
        // streak, not about reminders. Behind the reminder toggle - which is
        // off by default - a banked freeze was never spent for most users, so
        // one missed day zeroed a streak the streak sheet said was protected.
        let resolution = StreakProtection.resolve(
            practiceDays: practiceDays,
            frozenDays: settings.streakFrozenDays
        )
        if resolution.didConsumeFreeze {
            settings.streakFrozenDays = resolution.frozenDays
            try? context.save()
            logger.info("Streak freeze consumed, streak held at \(resolution.rescuedStreak, privacy: .public)")
        }

        // The daily reminder toggle is the consent. With it off we hold no
        // channel at all - no streak rescue, no comeback, nothing.
        guard settings.dailyReminderEnabled else {
            notifications.cancelAll()
            return nil
        }
        // Checked after the freeze pass on purpose: no await ahead of it, so
        // the spend lands before Today's first load reads the streak.
        await notifications.checkPermission()
        if !notifications.hasPermission, requestPermissionIfNeeded {
            _ = await notifications.requestPermission()
        }
        guard notifications.hasPermission else { return nil }

        if afterPractice {
            notifications.cancelStreakRescue()
        }

        if resolution.didConsumeFreeze, settings.streakRemindersEnabled {
            await notifications.sendFreezeUsed(
                rescuedStreak: resolution.rescuedStreak,
                freezesRemaining: resolution.freezesRemaining
            )
        }

        let currentStreak = Date.calculateStreak(
            from: practiceDays,
            frozenDays: resolution.frozenDays
        )

        // MARK: Reminder time

        // The daily nudge chases the user's own rhythm rather than a time the
        // product picked, landing shortly before they usually practise. Written
        // back to the stored hour/minute so Settings shows the truth and the
        // planner keeps one source for the slot.
        if settings.adaptiveReminderEnabled,
           let learned = PracticeRhythm.suggestion(from: practiceDays),
           learned.hour != settings.dailyReminderHour || learned.minute != settings.dailyReminderMinute {
            settings.dailyReminderHour = learned.hour
            settings.dailyReminderMinute = learned.minute
            try? context.save()
            logger.info("Reminder moved to \(learned.hour, privacy: .public):\(learned.minute, privacy: .public)")
        }

        // MARK: Milestones

        if settings.milestoneNotificationsEnabled,
           currentStreak > settings.lastMilestoneNotified,
           RetentionNotificationPlanner.milestones.contains(currentStreak) {
            await notifications.sendMilestone(streak: currentStreak)
            settings.lastMilestoneNotified = currentStreak
            try? context.save()
        } else if currentStreak == 0, settings.lastMilestoneNotified != 0 {
            // Streak broke - re-arm so the next run celebrates again.
            settings.lastMilestoneNotified = 0
            try? context.save()
        }

        // MARK: Plan

        let snapshot = RetentionSnapshot(
            currentStreak: currentStreak,
            longestStreak: max(currentStreak, longestStreak(from: practiceDays)),
            lastPracticeDate: practiceDays.max(),
            freezesAvailable: StreakProtection.freezesAvailable(
                practiceDayCount: Set(practiceDays.map(\.startOfDay)).count,
                frozenDayCount: resolution.frozenDays.count
            ),
            reminderHour: settings.dailyReminderHour,
            reminderMinute: settings.dailyReminderMinute,
            dailyReminderEnabled: true,
            streakRemindersEnabled: settings.streakRemindersEnabled,
            comebackRemindersEnabled: settings.comebackRemindersEnabled
        )

        await notifications.applyPlan(for: snapshot)
        return snapshot
    }

    /// Turn the whole ladder off, e.g. when reminders are switched off.
    static func disable(service: NotificationService? = nil) {
        (service ?? NotificationService()).cancelAll()
    }

    // MARK: - Helpers

    /// Dates only - `propertiesToFetch` keeps this off the `analysis` blob,
    /// which is the expensive column and irrelevant to a streak.
    private static func practiceDates(in context: ModelContext) -> [Date] {
        var descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.date]
        return ((try? context.fetch(descriptor)) ?? []).map(\.date)
    }

    /// Longest run of consecutive practice days anywhere in history.
    private static func longestStreak(from dates: [Date]) -> Int {
        let days = Set(dates.map(\.startOfDay)).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var run = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            if previous.adding(days: 1).startOfDay == day {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }
        return longest
    }
}

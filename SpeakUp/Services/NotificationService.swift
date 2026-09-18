import Foundation
import os.log
import UserNotifications

@Observable
class NotificationService {
    private let logger = Logger.app("Notifications")
    var hasPermission = false

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            hasPermission = granted
            return granted
        } catch {
            logger.error("Notification permission error: \(error.localizedDescription, privacy: .private(mask: .hash))")
            return false
        }
    }

    func checkPermission() async {
        let settings = await center.notificationSettings()
        hasPermission = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    // MARK: - Retention Ladder

    /// Rebuild the whole schedule from a snapshot of where the user stands.
    ///
    /// Clears every id the planner owns first, so a plan is always the complete
    /// truth rather than a diff against whatever an older build left behind.
    /// Called on foreground and after each take - cheap, and it keeps the streak
    /// numbers quoted in the copy fresh.
    func applyPlan(for snapshot: RetentionSnapshot) async {
        guard hasPermission else { return }

        center.removePendingNotificationRequests(
            withIdentifiers: RetentionNotificationPlanner.allManagedIDs
        )

        for notification in RetentionNotificationPlanner.plan(for: snapshot) {
            await schedule(notification)
        }
    }

    /// Cancel everything the ladder owns. Used when the user turns reminders
    /// off, and on data reset.
    func cancelAll() {
        center.removePendingNotificationRequests(
            withIdentifiers: RetentionNotificationPlanner.allManagedIDs
        )
    }

    /// Clear the rescue notifications the moment a take lands, so someone who
    /// practised at 7pm never gets told at 8:30 that their streak is ending.
    func cancelStreakRescue() {
        center.removePendingNotificationRequests(withIdentifiers: [
            RetentionNotificationPlanner.streakAtRiskID,
            RetentionNotificationPlanner.streakLastCallID
        ])
    }

    // MARK: - Immediate Moments

    func sendMilestone(streak: Int) async {
        guard hasPermission,
              let planned = RetentionNotificationPlanner.milestone(streak: streak) else { return }
        await schedule(planned)
    }

    func sendFreezeUsed(rescuedStreak: Int, freezesRemaining: Int) async {
        guard hasPermission else { return }
        await schedule(
            RetentionNotificationPlanner.freezeUsed(
                rescuedStreak: rescuedStreak,
                freezesRemaining: freezesRemaining
            )
        )
    }

    // MARK: - Management

    func clearBadge() async {
        try? await center.setBadgeCount(0)
    }

    /// One-time-compatible cleanup for requests scheduled by older builds whose
    /// identifiers the planner no longer owns.
    func removeRetiredNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: ["lapsed_nudge"])
    }

    // MARK: - Scheduling

    private func schedule(_ notification: PlannedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.relevanceScore = notification.relevance
        if let badge = notification.badge {
            content.badge = NSNumber(value: badge)
        }
        // `.timeSensitive` would suit the streak rescue, but it needs the
        // com.apple.developer.usernotifications.time-sensitive entitlement - 
        // adding that here would break signing until the capability is enabled
        // on the provisioning profile. relevanceScore still orders the summary.
        content.interruptionLevel = .active

        let resolved = resolve(notification.schedule)
        guard case let .fire(trigger) = resolved else { return }

        // A nil trigger is not a failure - it is how UserNotifications spells
        // "deliver immediately", which is what the milestone and freeze-used
        // moments want.
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            logger.error("Failed to schedule \(notification.id, privacy: .public): \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
    }

    private enum TriggerResolution {
        /// Associated value `nil` means deliver immediately.
        case fire(UNNotificationTrigger?)
        /// The slot has already passed today - send nothing.
        case skip
    }

    private func resolve(_ schedule: PlannedNotification.Schedule) -> TriggerResolution {
        switch schedule {
        case let .daily(hour, minute):
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            return .fire(UNCalendarNotificationTrigger(dateMatching: components, repeats: true))

        case let .onceAt(hour, minute):
            // Must be pinned to *today*. A non-repeating calendar trigger rolls
            // a passed slot to tomorrow, which would deliver "your 10-day
            // streak ends at midnight" the evening after it already ended - 
            // the notification would be a lie by the time it arrived.
            let now = Date()
            guard let fireDate = Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: now
            ), fireDate > now else {
                return .skip
            }
            return .fire(
                UNTimeIntervalNotificationTrigger(
                    timeInterval: fireDate.timeIntervalSince(now),
                    repeats: false
                )
            )

        case let .afterDays(days):
            // Zero days means "now" - a nil trigger delivers immediately.
            guard days > 0 else { return .fire(nil) }
            return .fire(
                UNTimeIntervalNotificationTrigger(
                    timeInterval: Double(days) * 24 * 3600,
                    repeats: false
                )
            )
        }
    }
}

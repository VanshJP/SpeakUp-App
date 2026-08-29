import Foundation
import UserNotifications

@Observable
class NotificationService {
    var hasPermission = false

    private let center = UNUserNotificationCenter.current()
    
    // MARK: - Permission
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            hasPermission = granted
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }
    
    func checkPermission() async {
        let settings = await center.notificationSettings()
        hasPermission = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }
    
    // MARK: - Daily Reminder
    
    func scheduleDailyReminder(hour: Int, minute: Int) async {
        if !hasPermission {
            let granted = await requestPermission()
            guard granted else { return }
        }
        
        // Cancel existing reminder
        await cancelDailyReminder()
        
        // Create content
        let content = UNMutableNotificationContent()
        content.title = "Ready for a short speaking rep?"
        content.body = getRandomReminderMessage()
        content.sound = .default
        
        // Create trigger
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "daily_reminder",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }
    
    func cancelDailyReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }
    
    // MARK: - Management

    func clearBadge() async {
        try? await center.setBadgeCount(0)
    }

    /// One-time-compatible cleanup for requests scheduled by older builds.
    /// Daily reminder is the only notification contract now.
    func removeLegacyPressureNotifications() {
        center.removePendingNotificationRequests(
            withIdentifiers: ["streak_at_risk", "lapsed_nudge"]
        )
    }
    
    // MARK: - Helpers
    
    private func getRandomReminderMessage() -> String {
        let messages = [
            "Today's prompt is here when you want it.",
            "A minute is enough. Skip today if you need to.",
            "One short take, at your pace.",
            "Practice is ready whenever you are."
        ]
        return messages.randomElement() ?? messages[0]
    }
}

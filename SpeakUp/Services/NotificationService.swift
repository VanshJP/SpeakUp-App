import Foundation
import UserNotifications

@Observable
class NotificationService {
    var hasPermission = false
    var pendingNotifications: [UNNotificationRequest] = []
    
    private let center = UNUserNotificationCenter.current()
    
    // MARK: - Permission
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            hasPermission = granted
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }
    
    func checkPermission() async {
        let settings = await center.notificationSettings()
        hasPermission = settings.authorizationStatus == .authorized
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
        content.title = "Time to Practice!"
        content.body = getRandomReminderMessage()
        content.sound = .default
        content.badge = 1
        
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
    
    // MARK: - One-Time Notifications
    
    func scheduleOneTimeReminder(after seconds: TimeInterval, title: String, body: String) async {
        guard hasPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }
    
    // MARK: - Achievement Notifications
    
    func sendStreakMilestoneNotification(days: Int) async {
        guard hasPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Streak Milestone!"
        content.body = "Amazing! You've practiced for \(days) days in a row!"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "streak_\(days)",
            content: content,
            trigger: nil // Immediate
        )
        
        try? await center.add(request)
    }
    
    func sendGoalCompletedNotification(goalTitle: String) async {
        guard hasPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Goal Completed!"
        content.body = "Congratulations! You've completed: \(goalTitle)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "goal_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        try? await center.add(request)
    }
    
    // MARK: - Management
    
    func getScheduledNotifications() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
    
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
    }
    
    func clearBadge() async {
        try? await center.setBadgeCount(0)
    }
    
    // MARK: - Helpers
    
    private func getRandomReminderMessage() -> String {
        let messages = [
            "Your voice is your superpower. Let's practice!",
            "A few minutes of practice makes a big difference.",
            "Ready to level up your speaking skills?",
            "Today's prompt is waiting for you!",
            "Practice makes progress. Let's go!",
            "Small steps, big results. Start practicing now.",
            "Your future self will thank you for practicing today.",
            "Speaking confidence is built one session at a time."
        ]
        return messages.randomElement() ?? messages[0]
    }
}

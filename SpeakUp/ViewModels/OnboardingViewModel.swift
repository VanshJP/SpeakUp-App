import Foundation
import SwiftUI
import AVFoundation
import UserNotifications

@Observable
class OnboardingViewModel {
    var currentPage = 0
    var hasMicPermission = false
    var isRequestingPermission = false

    // Notification permission
    var hasNotificationPermission = false
    var isRequestingNotificationPermission = false

    let totalPages = 7

    var isLastPage: Bool { currentPage == totalPages - 1 }

    func nextPage() {
        guard currentPage < totalPages - 1 else { return }
        Haptics.medium()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage -= 1
        }
    }

    func requestMicPermission() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        hasMicPermission = await AVAudioApplication.requestRecordPermission()

        if hasMicPermission {
            Haptics.success()
        }
    }

    func checkMicPermission() {
        hasMicPermission = AVAudioApplication.shared.recordPermission == .granted
    }

    // MARK: - Notification Permission

    func requestNotificationPermission() async {
        isRequestingNotificationPermission = true
        defer { isRequestingNotificationPermission = false }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            hasNotificationPermission = granted
            if granted {
                Haptics.success()
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }

    func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        hasNotificationPermission = settings.authorizationStatus == .authorized
    }
}

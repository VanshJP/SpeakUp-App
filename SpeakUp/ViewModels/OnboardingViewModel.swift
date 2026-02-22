import Foundation
import SwiftUI
import AVFoundation

@Observable
class OnboardingViewModel {
    var currentPage = 0
    var hasMicPermission = false
    var isRequestingPermission = false

    // Interactive state per page
    var scoreAnimationTriggered = false
    var toolsRevealed = 0
    var progressItemsRevealed = 0
    var micJustGranted = false

    let totalPages = 6

    var isLastPage: Bool { currentPage == totalPages - 1 }

    func nextPage() {
        guard currentPage < totalPages - 1 else { return }
        Haptics.medium()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentPage += 1
        }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentPage -= 1
        }
    }

    func triggerScoreAnimation() {
        guard !scoreAnimationTriggered else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                self.scoreAnimationTriggered = true
            }
        }
    }

    func revealTools() {
        guard toolsRevealed == 0 else { return }
        for i in 1...4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.toolsRevealed = i
                }
                Haptics.light()
            }
        }
    }

    func revealProgressItems() {
        guard progressItemsRevealed == 0 else { return }
        for i in 1...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.progressItemsRevealed = i
                }
                Haptics.light()
            }
        }
    }

    func requestMicPermission() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        if #available(iOS 17.0, *) {
            hasMicPermission = await AVAudioApplication.requestRecordPermission()
        } else {
            hasMicPermission = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        if hasMicPermission {
            Haptics.success()
            withAnimation(.spring(response: 0.5)) {
                micJustGranted = true
            }
        }
    }

    func checkMicPermission() {
        if #available(iOS 17.0, *) {
            hasMicPermission = AVAudioApplication.shared.recordPermission == .granted
        } else {
            hasMicPermission = AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }
}

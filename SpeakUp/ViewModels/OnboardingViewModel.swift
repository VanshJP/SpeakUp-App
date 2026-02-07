import Foundation
import SwiftUI
import AVFoundation

@Observable
class OnboardingViewModel {
    var currentPage = 0
    var hasMicPermission = false
    var isRequestingPermission = false

    let totalPages = 4

    var isLastPage: Bool { currentPage == totalPages - 1 }
    var canProceed: Bool {
        if isLastPage {
            return hasMicPermission
        }
        return true
    }

    func nextPage() {
        guard currentPage < totalPages - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage -= 1
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
    }

    func checkMicPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            hasMicPermission = true
        default:
            hasMicPermission = false
        }
    }
}

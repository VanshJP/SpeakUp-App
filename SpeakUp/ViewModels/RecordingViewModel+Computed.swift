import Foundation
import SwiftUI

extension RecordingViewModel {
    // MARK: - Computed Properties

    var isOvertime: Bool {
        remainingTime < 0 && timerEndBehavior == .keepGoing
    }

    /// The time value shown in the timer, accounting for countdown style.
    var displayTime: TimeInterval {
        if isOvertime {
            return abs(remainingTime)
        }
        switch countdownStyle {
        case .countDown:
            return max(0, remainingTime)
        case .countUp:
            return recordingDuration
        }
    }

    var formattedRemainingTime: String {
        if isOvertime {
            let overtimeSeconds = Int(abs(remainingTime))
            let minutes = overtimeSeconds / 60
            let seconds = overtimeSeconds % 60
            return String(format: "+%d:%02d", minutes, seconds)
        }
        let totalSeconds = Int(displayTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var timerLabel: String {
        if isOvertime { return "overtime" }
        return countdownStyle == .countDown ? "remaining" : "elapsed"
    }

    var timerColor: Color {
        if isOvertime {
            return .purple
        } else if remainingTime <= 10 {
            return .red
        } else if remainingTime <= 30 {
            return .orange
        }
        return .teal
    }
}

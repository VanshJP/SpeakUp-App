import Foundation
import SwiftUI

@Observable
class DrillViewModel {
    var selectedMode: DrillMode?
    var isActive = false
    var timeRemaining: Int = 0
    var score: Int = 0
    var liveFillerCount = 0
    var liveWPM: Double = 0
    var result: DrillResult?
    var isComplete = false

    private var timer: Timer?
    private var totalDuration: Int = 0

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - Double(timeRemaining) / Double(totalDuration)
    }

    func startDrill(mode: DrillMode) {
        selectedMode = mode
        totalDuration = mode.defaultDurationSeconds
        timeRemaining = totalDuration
        liveFillerCount = 0
        liveWPM = 0
        score = 0
        isActive = true
        isComplete = false
        result = nil

        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    @MainActor
    private func tick() {
        guard isActive else { return }

        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            finishDrill()
        }
    }

    func addFiller() {
        liveFillerCount += 1
    }

    func updateWPM(_ wpm: Double) {
        liveWPM = wpm
    }

    @MainActor
    func finishDrill() {
        isActive = false
        timer?.invalidate()
        timer = nil

        guard let mode = selectedMode else { return }

        // Calculate score based on mode
        let drillScore: Int
        let details: String
        let passed: Bool

        switch mode {
        case .fillerElimination:
            drillScore = liveFillerCount == 0 ? 100 : max(0, 100 - liveFillerCount * 25)
            passed = liveFillerCount == 0
            details = liveFillerCount == 0 ? "Perfect! Zero fillers!" : "\(liveFillerCount) filler(s) detected"

        case .paceControl:
            let deviation = abs(liveWPM - 150) // Target: 150 WPM
            drillScore = max(0, 100 - Int(deviation * 2))
            passed = deviation < 20
            details = "Average pace: \(Int(liveWPM)) WPM (target: 130-170)"

        case .pausePractice:
            drillScore = score
            passed = score >= 70
            details = passed ? "Good deliberate pausing!" : "Try to pause more at the markers"

        case .impromptuSprint:
            drillScore = max(50, 100 - liveFillerCount * 10)
            passed = liveFillerCount <= 2
            details = "Spoke with \(liveFillerCount) filler(s) on an impromptu topic"
        }

        result = DrillResult(
            mode: mode,
            score: drillScore,
            date: Date(),
            details: details,
            passed: passed
        )
        isComplete = true

        if passed {
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }

    func cleanup() {
        timer?.invalidate()
        timer = nil
    }
}

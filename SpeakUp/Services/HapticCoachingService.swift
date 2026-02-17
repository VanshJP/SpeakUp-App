import Foundation
import UIKit

@Observable
class HapticCoachingService {
    var isEnabled = false

    private var silenceDuration: TimeInterval = 0
    private var lastAudioTime: Date = Date()
    private var wordTimestamps: [Date] = []
    private var lastHapticTime: Date = .distantPast

    // Thresholds
    var silenceThreshold: TimeInterval = 4.0
    var highWPMThreshold: Double = 190
    var lowWPMThreshold: Double = 100
    var wpmWindowSeconds: TimeInterval = 15
    private let hapticCooldown: TimeInterval = 3.0

    func processAudioLevel(_ level: Float) {
        guard isEnabled else { return }

        let now = Date()
        if level > -40 {
            silenceDuration = 0
            lastAudioTime = now
        } else {
            silenceDuration = now.timeIntervalSince(lastAudioTime)
            if silenceDuration >= silenceThreshold && canFireHaptic() {
                // Double light tap for long silence
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    generator.impactOccurred()
                }
                lastHapticTime = now
            }
        }
    }

    func processFillerDetected() {
        guard isEnabled, canFireHaptic() else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        lastHapticTime = Date()
    }

    func processWordTimestamp() {
        guard isEnabled else { return }
        let now = Date()
        wordTimestamps.append(now)

        // Keep only timestamps within the rolling window
        let cutoff = now.addingTimeInterval(-wpmWindowSeconds)
        wordTimestamps.removeAll { $0 < cutoff }

        // Compute rolling WPM
        let windowDuration = now.timeIntervalSince(wordTimestamps.first ?? now)
        guard windowDuration > 5 else { return } // Need at least 5s of data

        let wpm = Double(wordTimestamps.count) / windowDuration * 60

        if (wpm > highWPMThreshold || wpm < lowWPMThreshold) && canFireHaptic() {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            lastHapticTime = now
        }
    }

    func reset() {
        silenceDuration = 0
        lastAudioTime = Date()
        wordTimestamps = []
        lastHapticTime = .distantPast
    }

    private func canFireHaptic() -> Bool {
        Date().timeIntervalSince(lastHapticTime) >= hapticCooldown
    }
}

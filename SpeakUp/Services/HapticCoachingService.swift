import Foundation
import UIKit
import SwiftUI

/// Real-time coaching during recording sessions.
/// Provides haptic feedback and written cue messages for pace, silence, and filler usage.
@Observable
@MainActor
class HapticCoachingService {
    var isEnabled = false

    /// Current coaching cue to display in the recording UI. `nil` when no cue is active.
    var currentCue: CoachingCue?

    // MARK: - Thresholds

    var silenceThreshold: TimeInterval = 4.0
    var highWPMThreshold: Double = 190
    var lowWPMThreshold: Double = 100
    var wpmWindowSeconds: TimeInterval = 15

    // MARK: - Internal State

    private var silenceDuration: TimeInterval = 0
    private var lastAudioTime: Date = Date()
    private var wordTimestamps: [Date] = []
    private var lastHapticTime: Date = .distantPast
    private var lastCueTime: Date = .distantPast
    private var lastFillerCount = 0
    /// Crutch words that already earned their named cue this session.
    private var cuedRepeatedFillers: Set<String> = []
    private var cueDismissTask: Task<Void, Never>?

    /// Uses of one word before it earns the named repeated-filler cue.
    static let repeatedFillerCueThreshold = 5

    /// Gate so one silence window fires one cue, not one per sample tick.
    /// Reset when voice returns (level > -40) and in `reset()`.
    private var silenceCueFired = false

    private let hapticCooldown: TimeInterval = 3.0
    private let cueCooldown: TimeInterval = 6.0
    private let cueDisplayDuration: TimeInterval = 3.5

    // Prepared haptic generators. `prepare()` is called in `init` so the
    // first fire doesn't incur the per-call instantiation cost on the
    // already-saturated main actor during recording.
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let warningGenerator = UINotificationFeedbackGenerator()

    init() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        warningGenerator.prepare()
    }

    // MARK: - Public API

    func processAudioLevel(_ level: Float) {
        guard isEnabled else { return }

        let now = Date()
        if level > -40 {
            silenceDuration = 0
            lastAudioTime = now
            silenceCueFired = false
        } else {
            silenceDuration = now.timeIntervalSince(lastAudioTime)
            if silenceDuration >= silenceThreshold && !silenceCueFired {
                silenceCueFired = true
                fireHaptic(.light, double: true)
                showCue(CoachingCue(
                    message: "You've been quiet, keep going!",
                    icon: "waveform.slash",
                    tint: .orange
                ))
            }
        }
    }

    func processFillerDetected(currentCount: Int, repeatedWord: String? = nil, repeatedCount: Int = 0) {
        guard isEnabled else { return }

        let delta = currentCount - lastFillerCount
        lastFillerCount = currentCount

        // One named cue per crutch word per session. Naming the word ("that's
        // 5× 'like'") trains faster than the generic warning; the gate keeps a
        // runaway "like" streak from nagging every two seconds.
        if let word = repeatedWord,
           repeatedCount >= Self.repeatedFillerCueThreshold,
           !cuedRepeatedFillers.contains(word) {
            let fired = showCue(CoachingCue(
                message: "That's \(repeatedCount)\u{00D7} \u{201C}\(word)\u{201D}, try a pause instead",
                icon: "exclamationmark.bubble.fill",
                tint: .orange
            ))
            if fired {
                cuedRepeatedFillers.insert(word)
                fireHaptic(.warning)
            }
            return
        }

        guard delta > 0 else { return }
        fireHaptic(.warning)
        showCue(CoachingCue(
            message: "Watch the filler words",
            icon: "exclamationmark.bubble",
            tint: .orange
        ))
    }

    func processWordTimestamp() {
        guard isEnabled else { return }
        let now = Date()
        wordTimestamps.append(now)

        // Keep only timestamps within the rolling window
        let cutoff = now.addingTimeInterval(-wpmWindowSeconds)
        wordTimestamps.removeAll { $0 < cutoff }

        // Need at least 5s of data
        let windowDuration = now.timeIntervalSince(wordTimestamps.first ?? now)
        guard windowDuration > 5 else { return }

        let wpm = Double(wordTimestamps.count) / windowDuration * 60

        if wpm > highWPMThreshold {
            fireHaptic(.medium)
            showCue(CoachingCue(
                message: "Slow down a bit",
                icon: "tortoise",
                tint: .yellow
            ))
        } else if wpm < lowWPMThreshold {
            fireHaptic(.medium)
            showCue(CoachingCue(
                message: "Pick up the pace",
                icon: "hare",
                tint: AppColors.categoryBrandBright
            ))
        }
    }

    func reset() {
        silenceDuration = 0
        lastAudioTime = Date()
        wordTimestamps = []
        lastHapticTime = .distantPast
        lastCueTime = .distantPast
        lastFillerCount = 0
        cuedRepeatedFillers = []
        silenceCueFired = false
        cueDismissTask?.cancel()
        currentCue = nil
    }

    // MARK: - Haptic Feedback

    private enum HapticType {
        case light, medium, warning
    }

    private func fireHaptic(_ type: HapticType, double: Bool = false) {
        guard canFireHaptic() else { return }
        lastHapticTime = Date()

        switch type {
        case .light:
            lightGenerator.impactOccurred()
            if double {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.lightGenerator.impactOccurred()
                }
            }
        case .medium:
            mediumGenerator.impactOccurred()
        case .warning:
            warningGenerator.notificationOccurred(.warning)
        }
    }

    private func canFireHaptic() -> Bool {
        Date().timeIntervalSince(lastHapticTime) >= hapticCooldown
    }

    // MARK: - Written Cue

    /// Presents a cue unless the cue cooldown is running. Returns whether it
    /// actually displayed — callers gate one-shot state on the answer so a
    /// swallowed cue can fire later instead of being lost forever.
    @discardableResult
    private func showCue(_ cue: CoachingCue) -> Bool {
        guard Date().timeIntervalSince(lastCueTime) >= cueCooldown else { return false }
        lastCueTime = Date()
        cueDismissTask?.cancel()

        withAnimation(.spring(response: 0.3)) {
            currentCue = cue
        }

        cueDismissTask = Task {
            try? await Task.sleep(for: .seconds(cueDisplayDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                currentCue = nil
            }
        }
        return true
    }
}

// MARK: - Coaching Cue Model

struct CoachingCue: Equatable {
    let message: String
    let icon: String
    let tint: Color
}

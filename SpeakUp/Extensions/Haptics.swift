import UIKit

enum Haptics {
    // MARK: - Impact

    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func light() {
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }

    static func medium() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }

    static func heavy() {
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred()
    }

    // MARK: - Notification

    static func success() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning - timer running low, approaching limit
    static func warning() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.warning)
    }

    static func error() {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.error)
    }

    // MARK: - Selection

    static func selection() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    // MARK: - Count-up

    /// The odometer under every animated score: a selection tick each time an
    /// ease-out count from 0 passes a multiple of `step`, quick at first and
    /// then settling like a wheel coming to rest. Start it alongside a
    /// `.easeOut(duration:)` count of the same length. Ticks at or past
    /// `cutoff` are skipped so they cannot blur into the landing haptic.
    static func playCountUp(to score: Int, duration: Double, cutoff: Double? = nil, step: Int = 10) async {
        var elapsed = 0.0
        for time in countUpTickTimes(to: score, step: step, duration: duration)
        where time < (cutoff ?? duration) {
            try? await Task.sleep(for: .seconds(time - elapsed))
            guard !Task.isCancelled else { return }
            elapsed = time
            selection()
        }
    }

    /// Seconds after the count starts at which an ease-out count from 0 to
    /// `score` passes each multiple of `step`. Solves the curve SwiftUI's
    /// `.easeOut` runs - cubic Bézier (0,0)(0.58,1), so y(s) = 3s² − 2s³ -
    /// for each mark, then maps the parameter back to time.
    nonisolated static func countUpTickTimes(to score: Int, step: Int = 10, duration: Double) -> [Double] {
        guard score >= step, step > 0 else { return [] }
        return stride(from: step, through: score, by: step).map { mark in
            let target = Double(mark) / Double(score)
            var low = 0.0, high = 1.0
            for _ in 0..<30 {
                let s = (low + high) / 2
                if 3 * s * s - 2 * s * s * s < target { low = s } else { high = s }
            }
            let s = (low + high) / 2
            return (3 * (1 - s) * s * s * 0.58 + s * s * s) * duration
        }
    }
}

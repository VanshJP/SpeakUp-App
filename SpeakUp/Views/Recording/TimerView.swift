import SwiftUI

struct TimerView: View {
    let remainingTime: TimeInterval
    let totalTime: TimeInterval
    let progress: Double
    let color: Color
    let isRecording: Bool
    var isOvertime: Bool = false
    var timerLabel: String = "remaining"

    private let size: CGFloat = 200
    private let lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            // Plain `.animation`, not `.motion`: this is a clock reading, not
            // decoration, so it keeps interpolating under Reduce Motion.
            RingProgress(progress: progress, color: color, lineWidth: lineWidth)
                .frame(width: size, height: size)
                .animation(.linear(duration: 0.1), value: progress)

            // Time display — rounded numerals with tabular spacing so digits
            // don't jitter as the clock ticks
            VStack(spacing: 6) {
                Text(formattedTime)
                    .font(.system(size: isOvertime ? 44 : 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOvertime ? color : .white)
                    .contentTransition(.numericText())

                Text(isRecording ? timerLabel : "ready")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
        }
    }

    private var formattedTime: String {
        if isOvertime {
            return "+" + abs(remainingTime).minutesSeconds
        }
        return max(0, remainingTime).minutesSeconds
    }
}

#Preview("Timer Views") {
    ZStack {
        Color.black.ignoresSafeArea()

        TimerView(
            remainingTime: 45,
            totalTime: 60,
            progress: 0.25,
            color: AppColors.primary,
            isRecording: true
        )
    }
}

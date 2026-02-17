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
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)

            // Glass background
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size - lineWidth * 2 - 8, height: size - lineWidth * 2 - 8)

            // Time display
            VStack(spacing: 4) {
                Text(formattedTime)
                    .font(.system(size: isOvertime ? 40 : 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(isOvertime ? color : .white)

                if isRecording {
                    Text(timerLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("ready")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var formattedTime: String {
        if isOvertime {
            let overtimeSeconds = Int(abs(remainingTime))
            let minutes = overtimeSeconds / 60
            let seconds = overtimeSeconds % 60
            return String(format: "+%d:%02d", minutes, seconds)
        }
        let totalSeconds = Int(max(0, remainingTime))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Compact Timer

struct CompactTimerView: View {
    let remainingTime: TimeInterval
    let totalTime: TimeInterval
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                    
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
            
            // Time
            Text(formattedTime)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
    }
    
    private var progress: Double {
        guard totalTime > 0 else { return 0 }
        return 1 - (remainingTime / totalTime)
    }
    
    private var formattedTime: String {
        let totalSeconds = Int(max(0, remainingTime))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Countdown Timer

struct CountdownTimerView: View {
    let seconds: Int
    let color: Color
    
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Text("\(seconds)")
            .font(.system(size: 120, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .scaleEffect(scale)
            .onChange(of: seconds) { _, _ in
                withAnimation(.spring(duration: 0.3)) {
                    scale = 1.2
                }
                withAnimation(.spring(duration: 0.3).delay(0.1)) {
                    scale = 1.0
                }
            }
    }
}

#Preview("Timer Views") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 40) {
            TimerView(
                remainingTime: 45,
                totalTime: 60,
                progress: 0.25,
                color: .teal,
                isRecording: true
            )
            
            CompactTimerView(
                remainingTime: 45,
                totalTime: 60,
                color: .teal
            )
            .frame(width: 200)
            
            CountdownTimerView(seconds: 3, color: .teal)
        }
    }
}

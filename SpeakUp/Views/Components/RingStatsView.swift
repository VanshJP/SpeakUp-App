import SwiftUI

struct RingStatsView: View {
    let streak: Int
    let sessions: Int
    let score: Int
    var improvement: Double = 0  // e.g., 12.5 for +12.5%

    private let streakTarget = 7  // Weekly goal
    private let sessionsTarget = 7

    @State private var animateRings = false

    private var improvementColor: Color {
        if improvement > 1 { return .green }
        if improvement < -1 { return .red }
        return .secondary
    }

    private var improvementIcon: String {
        if improvement > 1 { return "arrow.up.right" }
        if improvement < -1 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var improvementText: String {
        if abs(improvement) < 1 { return "0%" }
        let sign = improvement > 0 ? "+" : ""
        return "\(sign)\(Int(improvement))%"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Centered rings section
            ZStack {
                // Outer ring - Streak (orange)
                RingProgress(
                    progress: animateRings ? Double(min(streak, streakTarget)) / Double(streakTarget) : 0,
                    color: .orange,
                    lineWidth: 12
                )
                .frame(width: 140, height: 140)

                // Middle ring - Sessions (teal)
                RingProgress(
                    progress: animateRings ? Double(min(sessions, sessionsTarget)) / Double(sessionsTarget) : 0,
                    color: .teal,
                    lineWidth: 12
                )
                .frame(width: 105, height: 105)

                // Inner ring - Score (dynamic color)
                RingProgress(
                    progress: animateRings ? Double(score) / 100 : 0,
                    color: AppColors.scoreColor(for: score),
                    lineWidth: 12
                )
                .frame(width: 70, height: 70)

                // Center score display
                Text("\(score)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColors.scoreColor(for: score))
            }
            .frame(height: 150)

            // Metrics row: streak | sessions | score | progress
            HStack(spacing: 0) {
                MetricItem(
                    icon: "flame.fill",
                    color: .orange,
                    value: "\(streak)",
                    label: "Streak"
                )

                Divider()
                    .frame(height: 36)

                MetricItem(
                    icon: "mic.fill",
                    color: .teal,
                    value: "\(sessions)",
                    label: "Sessions"
                )

                Divider()
                    .frame(height: 36)

                MetricItem(
                    icon: "chart.line.uptrend.xyaxis",
                    color: AppColors.scoreColor(for: score),
                    value: "\(score)",
                    label: "Score"
                )

                Divider()
                    .frame(height: 36)

                MetricItem(
                    icon: improvementIcon,
                    color: improvementColor,
                    value: improvementText,
                    label: "Progress"
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animateRings = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stats: \(streak) day streak, \(sessions) sessions, score \(score) out of 100, \(improvementText) progress")
    }
}

// MARK: - Metric Item (compact row style)

private struct MetricItem: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ring Progress

struct RingProgress: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: progress)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        RingStatsView(streak: 5, sessions: 3, score: 72, improvement: 12.5)
        RingStatsView(streak: 2, sessions: 1, score: 45, improvement: -8.0)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

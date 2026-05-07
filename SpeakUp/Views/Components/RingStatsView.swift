import SwiftUI

struct RingStatsView: View {
    let sessions: Int
    let sessionsGoal: Int
    let score: Int
    var bestScore: Int = 0
    /// 7-day score trend in percentage points. Positive = improving,
    /// negative = regressing, 0 = no data or flat.
    var improvement: Double = 0

    /// Improvement magnitude that fills the outer ring completely.
    private let improvementTarget: Double = 30

    @State private var animateRings = false

    private var improvementRingProgress: Double {
        min(1.0, abs(improvement) / improvementTarget)
    }

    private var improvementColor: Color {
        if improvement > 0.5 { return AppColors.success }
        if improvement < -0.5 { return AppColors.error }
        return .white.opacity(0.35)
    }

    private var improvementText: String {
        if abs(improvement) < 0.5 { return "—" }
        let sign = improvement > 0 ? "+" : ""
        return "\(sign)\(Int(improvement.rounded()))%"
    }

    private var improvementIcon: String {
        if improvement > 0.5 { return "arrow.up.right" }
        if improvement < -0.5 { return "arrow.down.right" }
        return "minus"
    }

    var body: some View {
        VStack(spacing: 20) {
            // Centered rings section - bigger and more dramatic
            ZStack {
                // Ambient glow behind rings (stronger on dark gradient background)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.scoreColor(for: score).opacity(0.25), Color.teal.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)

                // Outer ring - 7-day improvement (green if up, red if down)
                RingProgress(
                    progress: animateRings ? improvementRingProgress : 0,
                    color: improvementColor,
                    lineWidth: 14
                )
                .frame(width: 170, height: 170)

                // Middle ring - Sessions this week / weekly goal (teal)
                RingProgress(
                    progress: animateRings ? Double(min(sessions, sessionsGoal)) / Double(max(sessionsGoal, 1)) : 0,
                    color: .teal,
                    lineWidth: 14
                )
                .frame(width: 130, height: 130)

                // Inner ring - Score (dynamic color)
                RingProgress(
                    progress: animateRings ? Double(score) / 100 : 0,
                    color: AppColors.scoreColor(for: score),
                    lineWidth: 14
                )
                .frame(width: 90, height: 90)

                // Center score display
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.scoreColor(for: score))
                    Text("avg")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 180)

            // Metrics row - integrated into the same card surface via a
            // hairline separator instead of a nested background.
            VStack(spacing: 14) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 0.5)

                HStack(spacing: 0) {
                    MetricItem(
                        icon: improvementIcon,
                        color: improvementColor,
                        value: improvementText,
                        label: "Trend"
                    )

                    MetricDivider()

                    MetricItem(
                        icon: "mic.fill",
                        color: .teal,
                        value: "\(sessions)/\(sessionsGoal)",
                        label: "This Week"
                    )

                    MetricDivider()

                    MetricItem(
                        icon: "trophy.fill",
                        color: AppColors.scoreColor(for: bestScore),
                        value: bestScore > 0 ? "\(bestScore)" : "—",
                        label: "Best Score"
                    )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)

                // Gradient tint
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.08), Color.cyan.opacity(0.03), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Inner glow
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // Top edge highlight
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                animateRings = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stats: 7-day trend \(improvementText), \(sessions) of \(sessionsGoal) sessions this week, average score \(score) out of 100, best score \(bestScore)")
    }
}

// MARK: - Metric Divider

private struct MetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 32)
    }
}

// MARK: - Metric Item (compact row style)

private struct MetricItem: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
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
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.5), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * progress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.2), value: progress)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        RingStatsView(sessions: 3, sessionsGoal: 5, score: 80, bestScore: 92, improvement: 14)
        RingStatsView(sessions: 1, sessionsGoal: 5, score: 45, bestScore: 68, improvement: -8)
        RingStatsView(sessions: 0, sessionsGoal: 5, score: 0, bestScore: 0, improvement: 0)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

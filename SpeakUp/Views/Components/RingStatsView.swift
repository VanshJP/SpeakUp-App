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

                // Outer ring - Streak (orange)
                RingProgress(
                    progress: animateRings ? Double(min(streak, streakTarget)) / Double(streakTarget) : 0,
                    color: .orange,
                    lineWidth: 14
                )
                .frame(width: 170, height: 170)

                // Middle ring - Sessions (teal)
                RingProgress(
                    progress: animateRings ? Double(min(sessions, sessionsTarget)) / Double(sessionsTarget) : 0,
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

            // Metrics row with better visual treatment
            HStack(spacing: 0) {
                MetricItem(
                    icon: "flame.fill",
                    color: .orange,
                    value: "\(streak)",
                    label: "Streak"
                )

                MetricDivider()

                MetricItem(
                    icon: "mic.fill",
                    color: .teal,
                    value: "\(sessions)",
                    label: "Sessions"
                )

                MetricDivider()

                MetricItem(
                    icon: "chart.line.uptrend.xyaxis",
                    color: AppColors.scoreColor(for: score),
                    value: "\(score)",
                    label: "Score"
                )

                MetricDivider()

                MetricItem(
                    icon: improvementIcon,
                    color: improvementColor,
                    value: improvementText,
                    label: "Progress"
                )
            }
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
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
        .accessibilityLabel("Stats: \(streak) day streak, \(sessions) sessions, score \(score) out of 100, \(improvementText) progress")
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
        RingStatsView(streak: 5, sessions: 3, score: 72, improvement: 12.5)
        RingStatsView(streak: 2, sessions: 1, score: 45, improvement: -8.0)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

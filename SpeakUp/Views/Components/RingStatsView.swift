import SwiftUI

struct RingStatsView: View {
    let sessions: Int
    let sessionsGoal: Int
    let score: Int
    var bestScore: Int = 0
    var improvement: Double = 0

    private let improvementTarget: Double = 30

    private var improvementRingProgress: Double {
        min(1.0, abs(improvement) / improvementTarget)
    }

    private var improvementColor: Color {
        if improvement > 0.5 { return AppColors.success }
        if improvement < -0.5 { return AppColors.error }
        return .white.opacity(0.35)
    }

    private var improvementText: String {
        if abs(improvement) < 0.5 { return "-" }
        let sign = improvement > 0 ? "+" : ""
        return "\(sign)\(Int(improvement.rounded()))%"
    }

    var body: some View {
        GlassCard(padding: 20) {
            VStack(spacing: 18) {
                // Three standalone gauges - value inside, label beneath.
                HStack(spacing: 0) {
                    GaugeItem(
                        progress: Double(score) / 100,
                        color: AppColors.scoreColor(for: score),
                        count: score > 0 ? Double(score) : nil,
                        format: { "\($0)" },
                        label: "Avg Score",
                        sweepDelay: 0
                    )

                    GaugeItem(
                        progress: Double(min(sessions, sessionsGoal)) / Double(max(sessionsGoal, 1)),
                        color: AppColors.primary,
                        count: Double(sessions),
                        format: { "\($0)/\(sessionsGoal)" },
                        label: "This Week",
                        sweepDelay: 0.08
                    )

                    GaugeItem(
                        progress: improvementRingProgress,
                        color: improvementColor,
                        count: abs(improvement) < 0.5 ? nil : improvement.rounded(),
                        format: { "\($0 > 0 ? "+" : "")\($0)%" },
                        label: "Trend",
                        sweepDelay: 0.16
                    )
                }

                // No row until there is a best to show: on day one it was a
                // "-" beside a red trophy, because a score of 0 sits in the
                // lowest band of the ramp.
                if bestScore > 0 {
                    VStack(spacing: 12) {
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(height: 0.5)

                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "trophy.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.scoreColor(for: bestScore))
                                Text("Best score")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(bestScore)")
                                .font(.statValue)
                                .foregroundStyle(.white)
                                .contentTransition(.numericText(value: Double(bestScore)))
                                .motion(AppMotion.settle, value: bestScore)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["\(sessions) of \(sessionsGoal) sessions this week"]
        parts.append(score > 0 ? "average score \(score) out of 100" : "no average score yet")
        if abs(improvement) >= 0.5 { parts.append("7-day trend \(improvementText)") }
        if bestScore > 0 { parts.append("best score \(bestScore)") }
        return "Stats: " + parts.joined(separator: ", ")
    }
}

// MARK: - Gauge Item (standalone ring + label beneath)

private struct GaugeItem: View {
    let progress: Double
    let color: Color
    /// The number in the ring; nil shows a dash - nothing to count yet.
    let count: Double?
    let format: (Int) -> String
    let label: String
    /// Stagger, so the three rings sweep left to right like one gesture.
    var sweepDelay: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Stats land a beat after Today mounts, so the first load reads
                // as the rings sweeping up from empty; a take that moves a
                // number later sweeps it from the old value to the new one.
                RingProgress(progress: progress, color: color, lineWidth: 8)
                    .frame(width: 78, height: 78)
                    .motion(.spring(duration: 1.1, bounce: 0.12).delay(sweepDelay), value: progress)

                // The number counts along with its ring (rule 5a) instead of
                // rolling once beside it. It rides the ring's timing without
                // the bounce - an overshoot reads as a wrong score, not a
                // spring. Always mounted, so a first value counts up from 0.
                ZStack {
                    Text("–")
                        .foregroundStyle(.white.opacity(0.45))
                        .opacity(count == nil ? 1 : 0)

                    CountUpText(value: count ?? 0, font: .statValue, format: format)
                        .opacity(count == nil ? 0 : 1)
                }
                .font(.statValue)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
                .motion(.spring(duration: 1.1, bounce: 0).delay(sweepDelay), value: count)
            }

            Text(label).eyebrowStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 20) {
        RingStatsView(sessions: 3, sessionsGoal: 5, score: 80, bestScore: 92, improvement: 14)
        RingStatsView(sessions: 1, sessionsGoal: 5, score: 45, bestScore: 68, improvement: -8)
        RingStatsView(sessions: 0, sessionsGoal: 5, score: 0, bestScore: 0, improvement: 0)
    }
    .padding()
    .background(AppBackground())
}

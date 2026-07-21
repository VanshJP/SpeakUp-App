import SwiftUI

struct RingStatsView: View {
    let sessions: Int
    let sessionsGoal: Int
    let score: Int
    var bestScore: Int = 0
    /// 7-day score trend in percentage points. Positive = improving,
    /// negative = regressing, 0 = no data or flat.
    var improvement: Double = 0

    /// Improvement magnitude that fills the trend gauge completely.
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

    var body: some View {
        VStack(spacing: 18) {
            // Three standalone gauges — value inside, label beneath.
            HStack(spacing: 0) {
                GaugeItem(
                    progress: animateRings ? Double(score) / 100 : 0,
                    color: AppColors.scoreColor(for: score),
                    value: score > 0 ? "\(score)" : "—",
                    label: "Avg Score"
                )

                GaugeItem(
                    progress: animateRings ? Double(min(sessions, sessionsGoal)) / Double(max(sessionsGoal, 1)) : 0,
                    color: AppColors.primary,
                    value: "\(sessions)/\(sessionsGoal)",
                    label: "This Week"
                )

                GaugeItem(
                    progress: animateRings ? improvementRingProgress : 0,
                    color: improvementColor,
                    value: improvementText,
                    label: "Trend"
                )
            }

            // Best-score footer under a hairline, integrated into the card.
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

                    Text(bestScore > 0 ? "\(bestScore)" : "—")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(bestScore)))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColors.surfaceLift)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppColors.cardStroke, lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 9)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                animateRings = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stats: 7-day trend \(improvementText), \(sessions) of \(sessionsGoal) sessions this week, average score \(score) out of 100, best score \(bestScore)")
    }
}

// MARK: - Gauge Item (standalone ring + label beneath)

private struct GaugeItem: View {
    let progress: Double
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RingProgress(progress: progress, color: color, lineWidth: 8)
                    .frame(width: 78, height: 78)

                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
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
            // Neutral recessed track — color belongs to progress only
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
    .background(AppBackground())
}

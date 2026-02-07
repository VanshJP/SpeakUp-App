import SwiftUI

struct WeeklyProgressCard: View {
    let data: WeeklyProgressData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Progress")
                .font(.headline)

            GlassCard(tint: .teal.opacity(0.05)) {
                HStack(spacing: 0) {
                    ProgressMetric(
                        label: "Sessions",
                        value: "\(data.sessionsThisWeek)",
                        delta: data.sessionsDelta,
                        icon: "mic.fill"
                    )

                    Divider().frame(height: 40)

                    ProgressMetric(
                        label: "Score",
                        value: data.scoreChange == 0 ? "--" : String(format: "%+.0f", data.scoreChange),
                        delta: Int(data.scoreChange),
                        icon: "chart.line.uptrend.xyaxis"
                    )

                    Divider().frame(height: 40)

                    ProgressMetric(
                        label: "Fillers",
                        value: data.fillerReduction == 0 ? "--" : String(format: "%+.0f%%", data.fillerReduction),
                        delta: Int(data.fillerReduction),
                        icon: "text.badge.minus"
                    )

                    Divider().frame(height: 40)

                    ProgressMetric(
                        label: "Minutes",
                        value: String(format: "%.0f", data.totalMinutes),
                        delta: nil,
                        icon: "clock"
                    )
                }
            }
        }
    }
}

private struct ProgressMetric: View {
    let label: String
    let value: String
    let delta: Int?
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(deltaColor)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(deltaColor)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var deltaColor: Color {
        guard let delta else { return .teal }
        if delta > 0 { return .green }
        if delta < 0 { return .red }
        return .secondary
    }
}

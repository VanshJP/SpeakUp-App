import SwiftUI

struct WeeklyProgressCard: View {
    let data: WeeklyProgressData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This Week", systemImage: "calendar")
                .font(.headline)

            GlassCard(tint: .teal.opacity(0.05)) {
                VStack(spacing: 14) {
                    HStack(spacing: 0) {
                        ProgressMetric(
                            label: "Sessions",
                            value: "\(data.sessionsThisWeek)",
                            delta: data.sessionsDelta,
                            icon: "mic.fill"
                        )

                        MetricDividerSmall()

                        ProgressMetric(
                            label: "Score",
                            value: data.scoreChange == 0 ? "--" : String(format: "%+.0f", data.scoreChange),
                            delta: Int(data.scoreChange),
                            icon: "chart.line.uptrend.xyaxis"
                        )

                        MetricDividerSmall()

                        ProgressMetric(
                            label: "Fillers",
                            value: data.fillerReduction == 0 ? "--" : String(format: "%+.0f%%", data.fillerReduction),
                            delta: Int(data.fillerReduction),
                            icon: "text.badge.minus"
                        )

                        MetricDividerSmall()

                        ProgressMetric(
                            label: "Minutes",
                            value: String(format: "%.0f", data.totalMinutes),
                            delta: nil,
                            icon: "clock"
                        )
                    }

                    // Mini week bar chart
                    WeekBarChart(data: data)
                }
            }
        }
    }
}

// MARK: - Week Bar Chart

private struct WeekBarChart: View {
    let data: WeeklyProgressData

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 4) {
                    // Bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(for: index))
                        .frame(height: barHeight(for: index))
                        .frame(maxWidth: .infinity)

                    // Day label
                    Text(dayLabels[index])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 44)
        .padding(.top, 4)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Use sessions this week to determine which days had activity
        // Simple: fill bars up to sessionsThisWeek count
        let todayWeekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 // Monday = 0
        if index <= todayWeekday {
            let hasPractice = index < data.sessionsThisWeek
            return hasPractice ? 28 : 8
        }
        return 4 // Future days
    }

    private func barColor(for index: Int) -> Color {
        let todayWeekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        if index > todayWeekday {
            return .gray.opacity(0.15)
        }
        let hasPractice = index < data.sessionsThisWeek
        return hasPractice ? .teal : .gray.opacity(0.25)
    }
}

// MARK: - Metric Divider Small

private struct MetricDividerSmall: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 32)
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

import SwiftUI
import Charts

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

                    // Score sparkline + activity bar chart combined
                    WeekScoreChart(data: data)
                }
            }
        }
    }
}

// MARK: - Week Score Chart

private struct WeekScoreChart: View {
    let data: WeeklyProgressData

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private var todayIndex: Int {
        (Calendar.current.component(.weekday, from: Date()) + 5) % 7
    }

    var body: some View {
        VStack(spacing: 6) {
            // Score sparkline (if scores exist)
            if !data.dailyScores.isEmpty {
                Chart {
                    ForEach(data.dailyScores, id: \.day) { point in
                        LineMark(
                            x: .value("Day", point.day),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.teal, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Day", point.day),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.teal.opacity(0.2), .teal.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(AppColors.scoreColor(for: point.score))
                        .symbolSize(24)
                        .annotation(position: .top, spacing: 2) {
                            Text("\(point.score)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.scoreColor(for: point.score))
                        }
                    }
                }
                .chartXScale(domain: 0...6)
                .chartYScale(domain: max(0, (data.dailyScores.map(\.score).min() ?? 0) - 15)...min(100, (data.dailyScores.map(\.score).max() ?? 100) + 15))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 52)
            }

            // Day labels with activity dots
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 4) {
                        // Activity indicator
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(for: index))
                            .frame(height: barHeight(for: index))
                            .frame(maxWidth: .infinity)

                        Text(dayLabels[index])
                            .font(.system(size: 9, weight: index == todayIndex ? .bold : .medium))
                            .foregroundStyle(index == todayIndex ? .teal : .secondary)
                    }
                }
            }
            .frame(height: 32)
        }
        .padding(.top, 4)
    }

    private func barHeight(for index: Int) -> CGFloat {
        if index > todayIndex {
            return 4
        }
        let hasPractice = data.dailyScores.contains { $0.day == index }
        return hasPractice ? 20 : 6
    }

    private func barColor(for index: Int) -> Color {
        if index > todayIndex {
            return .gray.opacity(0.12)
        }
        let hasPractice = data.dailyScores.contains { $0.day == index }
        if hasPractice {
            // Color by score
            if let score = data.dailyScores.first(where: { $0.day == index })?.score {
                return AppColors.scoreColor(for: score).opacity(0.7)
            }
            return .teal
        }
        return index == todayIndex ? .teal.opacity(0.2) : .gray.opacity(0.2)
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

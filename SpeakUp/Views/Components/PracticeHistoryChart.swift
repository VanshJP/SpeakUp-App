import SwiftUI
import Charts

// MARK: - Practice History Chart

struct PracticeHistoryChart: View {
    let dataPoints: [PracticeDataPoint]
    var accentColor: Color = AppColors.primary
    var height: CGFloat = 160

    var body: some View {
        if dataPoints.isEmpty {
            emptyState
        } else {
            GlassCard(tint: accentColor.opacity(0.04)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Score Trend")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let latest = dataPoints.last, let first = dataPoints.first {
                            let delta = latest.score - first.score
                            HStack(spacing: 3) {
                                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(delta >= 0 ? AppColors.success : AppColors.warning)
                        }
                    }

                    Chart(dataPoints) { point in
                        LineMark(
                            x: .value("Session", point.index),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(accentColor)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Session", point.index),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor.opacity(0.3), accentColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Session", point.index),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(accentColor)
                        .symbolSize(24)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.06))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                    }
                    .frame(height: height)
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard(tint: accentColor.opacity(0.04)) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(accentColor.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("No practice data yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text("Practice to see your score trends here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Practice Metrics Row

struct PracticeMetricsRow: View {
    let recordings: [Recording]

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 0) {
                metricItem(
                    icon: "mic.fill",
                    value: "\(recordings.count)",
                    label: "Sessions",
                    color: AppColors.primary
                )

                metricDivider

                metricItem(
                    icon: "chart.line.uptrend.xyaxis",
                    value: avgScore.map { "\($0)" } ?? "--",
                    label: "Avg Score",
                    color: avgScore.map { AppColors.scoreColor(for: $0) } ?? .secondary
                )

                metricDivider

                metricItem(
                    icon: "flame.fill",
                    value: bestScore.map { "\($0)" } ?? "--",
                    label: "Best",
                    color: bestScore.map { AppColors.scoreColor(for: $0) } ?? .secondary
                )

                metricDivider

                metricItem(
                    icon: "clock",
                    value: totalDuration,
                    label: "Total Time",
                    color: .blue
                )
            }
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 40)
    }

    private func metricItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var avgScore: Int? {
        let scores = recordings.compactMap { $0.analysis?.speechScore.overall }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    private var bestScore: Int? {
        recordings.compactMap { $0.analysis?.speechScore.overall }.max()
    }

    private var totalDuration: String {
        let total = recordings.reduce(0.0) { $0 + $1.actualDuration }
        if total < 60 { return "\(Int(total))s" }
        let minutes = Int(total) / 60
        return "\(minutes)m"
    }
}

// MARK: - Data Point

struct PracticeDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let score: Int
    let date: Date

    static func from(recordings: [Recording]) -> [PracticeDataPoint] {
        let sorted = recordings
            .filter { $0.analysis?.speechScore.overall != nil }
            .sorted { $0.date < $1.date }

        return sorted.enumerated().compactMap { index, recording in
            guard let score = recording.analysis?.speechScore.overall else { return nil }
            return PracticeDataPoint(index: index + 1, score: score, date: recording.date)
        }
    }
}

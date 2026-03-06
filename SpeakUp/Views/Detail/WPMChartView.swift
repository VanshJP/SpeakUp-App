import SwiftUI
import Charts

struct WPMChartView: View {
    let dataPoints: [WPMDataPoint]
    let targetWPM: Int
    let averageWPM: Double

    private var optimalLow: Double { Double(targetWPM) - 20 }
    private var optimalHigh: Double { Double(targetWPM) + 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary row
            HStack(spacing: 16) {
                statPill(label: "Avg", value: "\(Int(averageWPM))", color: wpmColor(averageWPM))
                statPill(label: "Target", value: "\(targetWPM)", color: AppColors.primary)
                statPill(label: "Range", value: "\(Int(minWPM))-\(Int(maxWPM))", color: .secondary)
            }

            Chart {
                // Optimal range band
                RectangleMark(
                    xStart: .value("Start", 0),
                    xEnd: .value("End", maxTimestamp),
                    yStart: .value("Low", optimalLow),
                    yEnd: .value("High", optimalHigh)
                )
                .foregroundStyle(AppColors.success.opacity(0.1))

                // Target line
                RuleMark(y: .value("Target", Double(targetWPM)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(AppColors.primary.opacity(0.5))

                // WPM line
                ForEach(dataPoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("WPM", point.wpm)
                    )
                    .foregroundStyle(AppColors.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("WPM", point.wpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.primary.opacity(0.2), AppColors.primary.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("WPM", point.wpm)
                    )
                    .foregroundStyle(wpmColor(point.wpm))
                    .symbolSize(24)
                }
            }
            .chartYScale(domain: chartYMin...chartYMax)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(formatTime(seconds))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel {
                        if let wpm = value.as(Double.self) {
                            Text("\(Int(wpm))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityLabel("Pace over time chart. Average \(Int(averageWPM)) words per minute, target \(targetWPM).")
        }
    }

    // MARK: - Subviews

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Helpers (precomputed from immutable data)

    private var minWPM: Double { dataPoints.map(\.wpm).min() ?? 0 }
    private var maxWPM: Double { dataPoints.map(\.wpm).max() ?? Double(targetWPM) }
    private var maxTimestamp: Double { dataPoints.map(\.timestamp).max() ?? 0 }
    private var chartYMin: Double { max(0, min(optimalLow, minWPM) - 20) }
    private var chartYMax: Double { max(optimalHigh, maxWPM) + 20 }

    private func wpmColor(_ wpm: Double) -> Color {
        if wpm >= optimalLow && wpm <= optimalHigh {
            return AppColors.success
        } else if wpm > optimalHigh {
            return AppColors.warning
        } else {
            return AppColors.info
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins):\(String(format: "%02d", secs))"
        }
        return "\(secs)s"
    }
}

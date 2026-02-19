import SwiftUI
import Charts

struct PaceChartView: View {
    let words: [TranscriptionWord]
    let totalDuration: TimeInterval

    private let targetWPM: Double = 150

    private struct PacePoint: Identifiable {
        let id = UUID()
        let time: Double
        let wpm: Double
        /// Deviation from target — positive = faster, negative = slower
        var deviation: Double { wpm - 150 }
    }

    /// Adaptive window size: scales with speech length for better granularity
    private var windowSize: TimeInterval {
        let speechStart = words.first?.start ?? 0
        let speechEnd = words.last?.end ?? totalDuration
        let span = speechEnd - speechStart
        // Use ~15% of the speech span, clamped between 3s and 10s
        return max(3, min(10, span * 0.15))
    }

    private var paceData: [PacePoint] {
        guard !words.isEmpty, totalDuration > 0 else { return [] }

        let speechStart = words.first?.start ?? 0
        let speechEnd = words.last?.end ?? totalDuration
        let span = speechEnd - speechStart
        guard span > 2 else { return [] }

        let window = windowSize
        // Adaptive step: sample ~40 points across the speech span
        let step: TimeInterval = max(1, span / 40)

        var points: [PacePoint] = []
        var t = speechStart
        while t <= speechEnd {
            let windowStart = max(speechStart, t - window / 2)
            let windowEnd = min(speechEnd, t + window / 2)
            let windowSpan = windowEnd - windowStart
            guard windowSpan > 0 else {
                t += step
                continue
            }
            let count = words.filter { $0.start >= windowStart && $0.start < windowEnd }.count
            let wpm = Double(count) / windowSpan * 60
            points.append(PacePoint(time: t - speechStart, wpm: wpm))
            t += step
        }
        return points
    }

    private var avgWPM: Double {
        guard !words.isEmpty else { return targetWPM }
        let speechStart = words.first?.start ?? 0
        let speechEnd = words.last?.end ?? totalDuration
        let span = speechEnd - speechStart
        guard span > 0 else { return targetWPM }
        return Double(words.count) / span * 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pace Over Time", systemImage: "speedometer")
                    .font(.headline)
                Spacer()
                Text("avg \(Int(avgWPM)) WPM")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            GlassCard {
                if paceData.count < 3 {
                    Text("Not enough data for pace chart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    VStack(spacing: 8) {
                        Chart {
                            // Baseline at target WPM
                            RuleMark(y: .value("Target", targetWPM))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.white.opacity(0.3))
                                .annotation(position: .leading, spacing: 4) {
                                    Text("\(Int(targetWPM))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.4))
                                }

                            // Area fill from baseline — shows deviation visually
                            ForEach(paceData) { point in
                                AreaMark(
                                    x: .value("Time", point.time),
                                    yStart: .value("Baseline", targetWPM),
                                    yEnd: .value("WPM", point.wpm)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [
                                            point.wpm > targetWPM
                                                ? Color.red.opacity(0.25)
                                                : Color.blue.opacity(0.25),
                                            .clear
                                        ],
                                        startPoint: point.wpm > targetWPM ? .top : .bottom,
                                        endPoint: point.wpm > targetWPM ? .bottom : .top
                                    )
                                )
                            }

                            // The pace line itself
                            ForEach(paceData) { point in
                                LineMark(
                                    x: .value("Time", point.time),
                                    y: .value("WPM", point.wpm)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .foregroundStyle(.teal)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                                    .foregroundStyle(.white.opacity(0.1))
                                AxisValueLabel()
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                                AxisGridLine().foregroundStyle(.clear)
                                AxisValueLabel {
                                    if let seconds = value.as(Double.self) {
                                        Text(formatTime(seconds))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: yDomain)
                        .frame(height: 180)

                        // Legend
                        HStack(spacing: 14) {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(.teal)
                                    .frame(width: 12, height: 2)
                                Text("Your pace")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Rectangle()
                                    .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                    .frame(width: 12, height: 1)
                                Text("\(Int(targetWPM)) WPM target")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(.red.opacity(0.25))
                                    .frame(width: 8, height: 8)
                                Text("Fast")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(.blue.opacity(0.25))
                                    .frame(width: 8, height: 8)
                                Text("Slow")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Y-axis domain: center around target, expand to fit data symmetrically
    private var yDomain: ClosedRange<Double> {
        guard !paceData.isEmpty else { return 100...200 }
        let minWPM = paceData.map(\.wpm).min() ?? targetWPM
        let maxWPM = paceData.map(\.wpm).max() ?? targetWPM
        let maxDev = max(abs(maxWPM - targetWPM), abs(targetWPM - minWPM), 30)
        let padding = maxDev * 0.2
        return (targetWPM - maxDev - padding)...(targetWPM + maxDev + padding)
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

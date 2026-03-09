import SwiftUI
import SwiftData
import Charts

struct ProgressChartsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.date, order: .reverse) private var recordings: [Recording]

    @State private var selectedTab: ChartTab = .score
    @State private var timeRange: TimeRange = .thirtyDays

    enum ChartTab: String, CaseIterable {
        case score = "Score"
        case fillers = "Fillers"
        case pace = "Pace"
        case skills = "Skills"
        case activity = "Activity"
    }

    enum TimeRange: String, CaseIterable {
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case ninetyDays = "90d"
        case all = "All"

        var days: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .all: return nil
            }
        }
    }

    private var filteredRecordings: [Recording] {
        let analyzed = recordings.filter { $0.analysis != nil }
        guard let days = timeRange.days else { return analyzed }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return analyzed.filter { $0.date >= cutoff }
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    // Tab picker
                    Picker("Chart", selection: $selectedTab) {
                        ForEach(ChartTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Time range picker (not for skills/activity)
                    if selectedTab != .skills {
                        HStack(spacing: 8) {
                            ForEach(TimeRange.allCases, id: \.self) { range in
                                Button {
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.3)) {
                                        timeRange = range
                                    }
                                } label: {
                                    Text(range.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(timeRange == range ? .white : .secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background {
                                            Capsule()
                                                .fill(timeRange == range ? Color.teal.opacity(0.3) : Color.white.opacity(0.06))
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }

                    // Chart content
                    if filteredRecordings.isEmpty {
                        emptyState
                    } else {
                        switch selectedTab {
                        case .score:
                            ScoreProgressChart(recordings: filteredRecordings)
                        case .fillers:
                            FillerTrendChart(recordings: filteredRecordings)
                        case .pace:
                            PaceTrendChart(recordings: filteredRecordings)
                        case .skills:
                            SubscoreRadarView(recordings: filteredRecordings)
                        case .activity:
                            SessionFrequencyChart(recordings: filteredRecordings)
                        }
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Progress Charts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.15))
                Text("Not enough data yet")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Complete a few recordings to see your progress trends.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
}

// MARK: - Score Progress Chart

struct ScoreProgressChart: View {
    let recordings: [Recording]

    private var dataPoints: [(date: Date, score: Int)] {
        recordings
            .compactMap { r in
                guard let score = r.analysis?.speechScore.overall else { return nil }
                return (date: r.date, score: score)
            }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Overall Score", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))

                if dataPoints.count >= 2 {
                    Chart {
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.teal.opacity(0.3), .teal.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(.teal)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(.teal)
                            .symbolSize(20)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 200)
                } else {
                    Text("Need at least 2 recordings to show trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }

                // Summary stats
                if !dataPoints.isEmpty {
                    HStack(spacing: 16) {
                        chartStat("Latest", value: "\(dataPoints.last?.score ?? 0)")
                        chartStat("Average", value: "\(dataPoints.map(\.score).reduce(0, +) / dataPoints.count)")
                        chartStat("Best", value: "\(dataPoints.map(\.score).max() ?? 0)")
                    }
                }
            }
        }
    }

    private func chartStat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.teal)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filler Trend Chart

struct FillerTrendChart: View {
    let recordings: [Recording]

    private var weeklyData: [(weekStart: Date, avgFillers: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recordings) { r in
            calendar.startOfDay(for: r.date.startOfWeek)
        }

        return grouped.map { (weekStart, recs) in
            let totalFillers = recs.compactMap { $0.analysis?.totalFillerCount }.reduce(0, +)
            let avg = recs.isEmpty ? 0 : Double(totalFillers) / Double(recs.count)
            return (weekStart: weekStart, avgFillers: avg)
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Filler Words per Session", systemImage: "exclamationmark.bubble.fill")
                    .font(.subheadline.weight(.semibold))

                if weeklyData.count >= 2 {
                    Chart {
                        ForEach(Array(weeklyData.enumerated()), id: \.offset) { _, point in
                            BarMark(
                                x: .value("Week", point.weekStart, unit: .weekOfYear),
                                y: .value("Avg Fillers", point.avgFillers)
                            )
                            .foregroundStyle(
                                point.avgFillers > 10 ? .red.opacity(0.7) :
                                point.avgFillers > 5 ? .orange.opacity(0.7) :
                                .green.opacity(0.7)
                            )
                            .cornerRadius(4)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 180)
                } else {
                    Text("Need more recordings across different weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
    }
}

// MARK: - Pace Trend Chart

struct PaceTrendChart: View {
    let recordings: [Recording]

    @Query private var userSettings: [UserSettings]

    private var dataPoints: [(date: Date, wpm: Double)] {
        recordings
            .compactMap { r in
                guard let wpm = r.analysis?.wordsPerMinute, wpm > 0 else { return nil }
                return (date: r.date, wpm: wpm)
            }
            .sorted { $0.date < $1.date }
    }

    private var targetWPM: Double {
        Double(userSettings.first?.targetWPM ?? 150)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Pace (WPM)", systemImage: "metronome")
                    .font(.subheadline.weight(.semibold))

                if dataPoints.count >= 2 {
                    Chart {
                        // Target band
                        RuleMark(y: .value("Target", targetWPM))
                            .foregroundStyle(.teal.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("WPM", point.wpm)
                            )
                            .foregroundStyle(.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("WPM", point.wpm)
                            )
                            .foregroundStyle(.cyan)
                            .symbolSize(20)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 200)

                    HStack(spacing: 8) {
                        Circle().fill(.teal.opacity(0.5)).frame(width: 8, height: 8)
                        Text("Target: \(Int(targetWPM)) WPM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Need at least 2 recordings to show pace trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
    }
}

// MARK: - Subscore Radar View

struct SubscoreRadarView: View {
    let recordings: [Recording]

    private var latestSubscores: SpeechSubscores? {
        recordings.first(where: { $0.analysis != nil })?.analysis?.speechScore.subscores
    }

    private struct RadarPoint: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    private var radarPoints: [RadarPoint] {
        guard let s = latestSubscores else { return [] }
        return [
            RadarPoint(label: "Clarity", value: Double(s.clarity), color: .blue),
            RadarPoint(label: "Pace", value: Double(s.pace), color: .cyan),
            RadarPoint(label: "Fillers", value: Double(s.fillerUsage), color: .orange),
            RadarPoint(label: "Pauses", value: Double(s.pauseQuality), color: .purple),
            RadarPoint(label: "Vocal", value: Double(s.vocalVariety ?? 50), color: .pink),
            RadarPoint(label: "Delivery", value: Double(s.delivery ?? 50), color: .red),
            RadarPoint(label: "Vocab", value: Double(s.vocabulary ?? 50), color: .green),
            RadarPoint(label: "Structure", value: Double(s.structure ?? 50), color: .yellow),
        ]
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Skill Breakdown (Latest)", systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))

                if radarPoints.isEmpty {
                    Text("No analysis data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    // Bar chart representation of subscores
                    VStack(spacing: 10) {
                        ForEach(radarPoints) { point in
                            HStack(spacing: 10) {
                                Text(point.label)
                                    .font(.caption.weight(.medium))
                                    .frame(width: 60, alignment: .trailing)
                                    .foregroundStyle(.secondary)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.08))

                                        Capsule()
                                            .fill(point.color.opacity(0.6))
                                            .frame(width: geo.size.width * (point.value / 100))
                                    }
                                }
                                .frame(height: 12)

                                Text("\(Int(point.value))")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppColors.scoreColor(for: Int(point.value)))
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Session Frequency Chart

struct SessionFrequencyChart: View {
    let recordings: [Recording]

    @Query private var userSettings: [UserSettings]

    private var weeklyGoal: Int {
        userSettings.first?.weeklyGoalSessions ?? 5
    }

    private var weeklyCounts: [(weekStart: Date, count: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recordings) { r in
            calendar.startOfDay(for: r.date.startOfWeek)
        }

        return grouped.map { (weekStart, recs) in
            (weekStart: weekStart, count: recs.count)
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sessions per Week", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))

                if weeklyCounts.count >= 2 {
                    Chart {
                        RuleMark(y: .value("Goal", weeklyGoal))
                            .foregroundStyle(.teal.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                        ForEach(Array(weeklyCounts.enumerated()), id: \.offset) { _, point in
                            BarMark(
                                x: .value("Week", point.weekStart, unit: .weekOfYear),
                                y: .value("Sessions", point.count)
                            )
                            .foregroundStyle(
                                point.count >= weeklyGoal ? Color.teal.opacity(0.7) : Color.white.opacity(0.3)
                            )
                            .cornerRadius(4)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 180)

                    HStack(spacing: 8) {
                        Circle().fill(.teal.opacity(0.5)).frame(width: 8, height: 8)
                        Text("Goal: \(weeklyGoal)/week")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Need more recording weeks to show frequency trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
    }
}

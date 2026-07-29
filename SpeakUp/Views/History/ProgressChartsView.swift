import SwiftUI
import SwiftData
import Charts

/// Lightweight per-recording projection for charts. Loaded once on a
/// background ModelContext so chart body evals never decode SpeechAnalysis
/// blobs on the main thread (only analyzed recordings are included).
nonisolated struct ChartRecordingPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let score: Int
    let wpm: Double
    let fillerCount: Int
}

/// The full charts experience — highlights hero, chart-type picker, time
/// range, and the selected chart. No background / scroll / nav of its own so
/// it can be embedded (History Progress tab) or wrapped (`ProgressChartsView`).
struct ProgressChartsContent: View {
    @Environment(\.modelContext) private var modelContext

    // Sorted date-descending, analyzed recordings only.
    @State private var points: [ChartRecordingPoint] = []
    @State private var latestSubscores: SpeechSubscores?
    @State private var isLoading = true

    @State private var selectedTab: ChartTab = .score
    @State private var timeRange: TimeRange = .thirtyDays

    enum ChartTab: String, CaseIterable, Identifiable {
        case score = "Score"
        case fillers = "Fillers"
        case pace = "Pace"
        case skills = "Skills"
        case activity = "Activity"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .score: return "chart.xyaxis.line"
            case .fillers: return "exclamationmark.bubble.fill"
            case .pace: return "metronome"
            case .skills: return "star.fill"
            case .activity: return "calendar"
            }
        }
    }

    enum TimeRange: String, CaseIterable, Identifiable {
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case ninetyDays = "90d"
        case all = "All"

        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            case .all: return nil
            }
        }

        var menuLabel: String {
            switch self {
            case .sevenDays: return "Last 7 days"
            case .thirtyDays: return "Last 30 days"
            case .ninetyDays: return "Last 90 days"
            case .all: return "All time"
            }
        }
    }

    private var filteredPoints: [ChartRecordingPoint] {
        guard let days = timeRange.days else { return points }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return points.filter { $0.date >= cutoff }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Highlights hero section
            if points.count >= 2 {
                highlightsSection
            }

            // Chart picker + time range. The range used to be a second
            // full-width picker row; as a menu it costs one control instead
            // of four and only appears where it applies.
            //
            // The picker is unframed because the History screen already stacks
            // a framed picker directly above this row. It is bounded to the
            // leftover width (and yields it via the low layout priority) so the
            // menu keeps its intrinsic width instead of being pushed off-screen.
            HStack(spacing: 10) {
                SectionPicker(
                    sections: ChartTab.allCases,
                    selection: $selectedTab,
                    label: { $0.rawValue },
                    icon: { $0.icon },
                    layout: .scrollable,
                    framed: false
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(0)

                if selectedTab != .skills {
                    timeRangeMenu
                        .fixedSize()
                }
            }

            // Chart content
            if filteredPoints.isEmpty {
                if !isLoading {
                    emptyState
                }
            } else {
                switch selectedTab {
                case .score:
                    ScoreProgressChart(points: filteredPoints)
                case .fillers:
                    FillerTrendChart(points: filteredPoints)
                case .pace:
                    PaceTrendChart(points: filteredPoints)
                case .skills:
                    SubscoreRadarView(subscores: latestSubscores)
                case .activity:
                    SessionFrequencyChart(points: filteredPoints)
                }
            }
        }
        .task { await loadPoints() }
    }

    private var timeRangeMenu: some View {
        Menu {
            ForEach(TimeRange.allCases) { range in
                Button {
                    Haptics.light()
                    timeRange = range
                } label: {
                    HStack {
                        Text(range.menuLabel)
                        if timeRange == range { Spacer(); Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(timeRange.rawValue)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background { Capsule().fill(.ultraThinMaterial) }
            .overlay { Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5) }
        }
        .accessibilityLabel("Time range")
    }

    // MARK: - Background Load

    private func loadPoints() async {
        let container = modelContext.container
        let result = await Task.detached(priority: .userInitiated) { () -> ([ChartRecordingPoint], SpeechSubscores?) in
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            guard let recordings = try? context.fetch(descriptor) else { return ([], nil) }

            var pts: [ChartRecordingPoint] = []
            pts.reserveCapacity(recordings.count)
            var latest: SpeechSubscores?

            for r in recordings where !r.isDeleted {
                guard let analysis = r.analysis else { continue }
                if latest == nil { latest = analysis.speechScore.subscores }
                pts.append(ChartRecordingPoint(
                    id: r.id,
                    date: r.date,
                    score: analysis.speechScore.overall,
                    wpm: analysis.wordsPerMinute,
                    fillerCount: analysis.totalFillerCount
                ))
            }
            return (pts, latest)
        }.value

        points = result.0
        latestSubscores = result.1
        isLoading = false
    }

    // MARK: - Highlights Section

    private var highlightsSection: some View {
        // `points` is date-descending: first = latest, last = first session.
        let scores = points.map(\.score)
        let bestScore = scores.max() ?? 0
        let latestScore = scores.first ?? 0
        let firstScore = scores.last ?? 0
        let totalImprovement = latestScore - firstScore

        // Find best subscore
        let bestSubscore = bestSubscoreInfo(from: latestSubscores)

        return VStack(spacing: 12) {
            // Hero highlight card
            FeaturedGlassCard {
                HStack(spacing: 16) {
                    // Left: big number
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Journey")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(latestScore)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("pts")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if totalImprovement != 0 {
                            HStack(spacing: 4) {
                                Image(systemName: totalImprovement > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2.weight(.bold))
                                Text("\(totalImprovement > 0 ? "+" : "")\(totalImprovement) since first session")
                                    .font(.caption)
                            }
                            .foregroundStyle(totalImprovement > 0 ? AppColors.success : AppColors.error)
                        }
                    }

                    Spacer()

                    // Right: personal best badge
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(AppColors.warning.opacity(0.15))
                                .frame(width: 52, height: 52)

                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundStyle(AppColors.warning)
                        }

                        Text("\(bestScore)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Best")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Three stat cards row
            HStack(spacing: 10) {
                HighlightStatCard(
                    icon: "number",
                    label: "Sessions",
                    value: "\(points.count)",
                    color: AppColors.primary
                )

                HighlightStatCard(
                    icon: bestSubscore.icon,
                    label: "Strongest",
                    value: bestSubscore.name,
                    color: bestSubscore.color
                )

                HighlightStatCard(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Average",
                    value: scores.isEmpty ? "—" : "\(scores.reduce(0, +) / scores.count)",
                    color: AppColors.scoreColor(for: scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count)
                )
            }
        }
    }

    private struct SubscoreInfo {
        let name: String
        let icon: String
        let color: Color
    }

    private func bestSubscoreInfo(from subscores: SpeechSubscores?) -> SubscoreInfo {
        guard let s = subscores else {
            return SubscoreInfo(name: "—", icon: "star.fill", color: AppColors.primary)
        }

        let all: [(String, Int, String, Color)] = [
            ("Clarity", s.clarity, "waveform", AppColors.categoryTeal),
            ("Pace", s.pace, "metronome", AppColors.categoryBrandBright),
            ("Fillers", s.fillerUsage, "bubble.left.fill", AppColors.categoryAmber),
            ("Pauses", s.pauseQuality, "pause.circle.fill", AppColors.categoryIndigo),
            ("Vocal", s.vocalVariety ?? 0, "speaker.wave.3.fill", AppColors.categoryPlum),
            ("Delivery", s.delivery ?? 0, "person.fill", AppColors.categoryCopper),
            ("Vocab", s.vocabulary ?? 0, "character.book.closed", AppColors.categorySage),
            ("Structure", s.structure ?? 0, "list.bullet", AppColors.categoryNeutralCool),
        ]

        let best = all.max(by: { $0.1 < $1.1 }) ?? all[0]
        return SubscoreInfo(name: best.0, icon: best.2, color: best.3)
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

// MARK: - Progress Charts View (standalone / navigation destination)

struct ProgressChartsView: View {
    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                ProgressChartsContent()
                    .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Progress Charts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Highlight Stat Card

private struct HighlightStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        GlassCard(padding: 12) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Score Progress Chart

struct ScoreProgressChart: View {
    let points: [ChartRecordingPoint]

    @State private var selectedIndex: Int?

    private var dataPoints: [(date: Date, score: Int, id: UUID)] {
        points
            .map { (date: $0.date, score: $0.score, id: $0.id) }
            .sorted { $0.date < $1.date }
    }

    /// Moving average (3-point) to smooth outliers
    private var trendLine: [(date: Date, score: Double)] {
        guard dataPoints.count >= 3 else { return [] }
        var result: [(date: Date, score: Double)] = []
        for i in 1..<(dataPoints.count - 1) {
            let avg = Double(dataPoints[i-1].score + dataPoints[i].score + dataPoints[i+1].score) / 3.0
            result.append((date: dataPoints[i].date, score: avg))
        }
        return result
    }

    private var yDomain: ClosedRange<Int> {
        let scores = dataPoints.map(\.score)
        let minScore = max(0, (scores.min() ?? 0) - 10)
        let maxScore = min(100, (scores.max() ?? 100) + 10)
        return minScore...maxScore
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Overall Score", systemImage: "chart.xyaxis.line")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    if dataPoints.count >= 3 {
                        HStack(spacing: 4) {
                            Circle().fill(AppColors.primary.opacity(0.4)).frame(width: 6, height: 6)
                            Text("Trend")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if dataPoints.count >= 2 {
                    Chart {
                        // Area under curve
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColors.primary.opacity(0.25), AppColors.primary.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                        }

                        // Data line
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(AppColors.primary)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }

                        // Smoothed trend line
                        ForEach(Array(trendLine.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Trend", point.score),
                                series: .value("Series", "Trend")
                            )
                            .foregroundStyle(AppColors.primary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .interpolationMethod(.catmullRom)
                        }

                        // Data points with score-based coloring
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(
                                selectedIndex == index
                                    ? AppColors.scoreColor(for: point.score)
                                    : AppColors.primary
                            )
                            .symbolSize(selectedIndex == index ? 60 : 24)
                        }

                        // Selected point annotation
                        if let idx = selectedIndex, idx < dataPoints.count {
                            let point = dataPoints[idx]
                            RuleMark(x: .value("Selected", point.date))
                                .foregroundStyle(.white.opacity(0.2))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartDateScrub(over: dataPoints, selection: $selectedIndex) { $0.date }
                    .frame(height: 220)

                    // Selected point detail or summary stats
                    if let idx = selectedIndex, idx < dataPoints.count {
                        let point = dataPoints[idx]
                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(AppColors.scoreColor(for: point.score))
                                    .frame(width: 8, height: 8)
                                Text("\(point.score)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(AppColors.scoreColor(for: point.score))
                            }

                            Text(point.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if idx > 0 {
                                let delta = point.score - dataPoints[idx - 1].score
                                HStack(spacing: 3) {
                                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption2.weight(.bold))
                                    Text("\(delta >= 0 ? "+" : "")\(delta)")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(delta >= 0 ? AppColors.success : AppColors.error)
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    } else if !dataPoints.isEmpty {
                        HStack(spacing: 16) {
                            chartStat("Latest", value: "\(dataPoints.last?.score ?? 0)", color: AppColors.scoreColor(for: dataPoints.last?.score ?? 0))
                            chartStat("Average", value: "\(dataPoints.map(\.score).reduce(0, +) / dataPoints.count)", color: AppColors.primary)
                            chartStat("Best", value: "\(dataPoints.map(\.score).max() ?? 0)", color: AppColors.warning)
                        }
                    }
                } else {
                    EmptyStateInline(
                        icon: "chart.line.uptrend.xyaxis",
                        message: "Two sessions and this starts tracking your score."
                    )
                }
            }
        }
    }

    private func chartStat(_ label: String, value: String, color: Color = AppColors.primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filler Trend Chart

struct FillerTrendChart: View {
    let points: [ChartRecordingPoint]

    @State private var selectedIndex: Int?

    private var weeklyData: [(weekStart: Date, avgFillers: Double, sessionCount: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { p in
            calendar.startOfDay(for: p.date.startOfWeek)
        }

        return grouped.map { (weekStart, recs) in
            let totalFillers = recs.map(\.fillerCount).reduce(0, +)
            let avg = recs.isEmpty ? 0 : Double(totalFillers) / Double(recs.count)
            return (weekStart: weekStart, avgFillers: avg, sessionCount: recs.count)
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    private var overallTrend: Double {
        guard weeklyData.count >= 2 else { return 0 }
        return weeklyData.last!.avgFillers - weeklyData.first!.avgFillers
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Filler Words per Session", systemImage: "exclamationmark.bubble.fill")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    // Trend indicator (lower is better for fillers)
                    if weeklyData.count >= 2 {
                        HStack(spacing: 4) {
                            Image(systemName: overallTrend < -1 ? "arrow.down.right" : overallTrend > 1 ? "arrow.up.right" : "arrow.right")
                                .font(.caption2.weight(.bold))
                            Text(overallTrend < -1 ? "Improving" : overallTrend > 1 ? "Rising" : "Steady")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(overallTrend < -1 ? AppColors.success : overallTrend > 1 ? AppColors.warning : .secondary)
                    }
                }

                if weeklyData.count >= 2 {
                    Chart {
                        ForEach(Array(weeklyData.enumerated()), id: \.offset) { index, point in
                            BarMark(
                                x: .value("Week", point.weekStart, unit: .weekOfYear),
                                y: .value("Avg Fillers", point.avgFillers)
                            )
                            .foregroundStyle(
                                selectedIndex == index
                                    ? (point.avgFillers > 10 ? AppColors.error : point.avgFillers > 5 ? AppColors.warning : AppColors.success)
                                    : (point.avgFillers > 10 ? AppColors.error.opacity(0.6) : point.avgFillers > 5 ? AppColors.warning.opacity(0.6) : AppColors.success.opacity(0.6))
                            )
                            .cornerRadius(6)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartDateScrub(over: weeklyData, selection: $selectedIndex) { $0.weekStart }
                    .frame(height: 200)

                    // Selected week detail
                    if let idx = selectedIndex, idx < weeklyData.count {
                        let week = weeklyData[idx]
                        HStack(spacing: 12) {
                            Text(week.weekStart.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", week.avgFillers))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(week.avgFillers > 10 ? AppColors.error : week.avgFillers > 5 ? AppColors.warning : AppColors.success)
                                Text("avg fillers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(week.sessionCount) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    } else {
                        // Legend
                        HStack(spacing: 12) {
                            fillerLegendItem(color: AppColors.success, label: "0-5")
                            fillerLegendItem(color: AppColors.warning, label: "5-10")
                            fillerLegendItem(color: AppColors.error, label: "10+")
                        }
                    }
                } else {
                    EmptyStateInline(
                        icon: "exclamationmark.bubble",
                        message: "Practice across a couple of weeks to see filler trends."
                    )
                }
            }
        }
    }

    private func fillerLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pace Trend Chart

struct PaceTrendChart: View {
    let points: [ChartRecordingPoint]

    @Query private var userSettings: [UserSettings]
    @State private var selectedIndex: Int?

    private var dataPoints: [(date: Date, wpm: Double)] {
        points
            .compactMap { p in
                guard p.wpm > 0 else { return nil }
                return (date: p.date, wpm: p.wpm)
            }
            .sorted { $0.date < $1.date }
    }

    private var targetWPM: Double {
        Double(userSettings.first?.targetWPM ?? 150)
    }

    /// Optimal speaking range (140-160 WPM)
    private var optimalRange: ClosedRange<Double> {
        (targetWPM - 10)...(targetWPM + 10)
    }

    private var yDomain: ClosedRange<Double> {
        let wpms = dataPoints.map(\.wpm)
        let minWPM = max(60, (wpms.min() ?? 100) - 20)
        let maxWPM = min(250, (wpms.max() ?? 200) + 20)
        return minWPM...maxWPM
    }

    private var avgWPM: Double {
        let wpms = dataPoints.map(\.wpm)
        guard !wpms.isEmpty else { return 0 }
        return wpms.reduce(0, +) / Double(wpms.count)
    }

    private var inRangePercent: Int {
        guard !dataPoints.isEmpty else { return 0 }
        let inRange = dataPoints.filter { optimalRange.contains($0.wpm) }.count
        return Int(Double(inRange) / Double(dataPoints.count) * 100)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Pace (WPM)", systemImage: "metronome")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(inRangePercent)% in range")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(inRangePercent >= 70 ? AppColors.success : inRangePercent >= 40 ? AppColors.warning : AppColors.error)
                }

                if dataPoints.count >= 2 {
                    Chart {
                        // Optimal range band
                        RectangleMark(
                            yStart: .value("Low", optimalRange.lowerBound),
                            yEnd: .value("High", optimalRange.upperBound)
                        )
                        .foregroundStyle(AppColors.primary.opacity(0.08))

                        // Target line
                        RuleMark(y: .value("Target", targetWPM))
                            .foregroundStyle(AppColors.primary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("Target")
                                    .font(.system(size: 8))
                                    .foregroundStyle(AppColors.primary.opacity(0.6))
                            }

                        // Line
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("WPM", point.wpm)
                            )
                            .foregroundStyle(AppColors.categoryBrandBright)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }

                        // Points colored by whether they're in the optimal range
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("WPM", point.wpm)
                            )
                            .foregroundStyle(
                                optimalRange.contains(point.wpm)
                                    ? AppColors.success
                                    : (point.wpm > optimalRange.upperBound ? AppColors.warning : AppColors.warning)
                            )
                            .symbolSize(selectedIndex == index ? 60 : 24)
                        }

                        // Selected indicator
                        if let idx = selectedIndex, idx < dataPoints.count {
                            RuleMark(x: .value("Selected", dataPoints[idx].date))
                                .foregroundStyle(.white.opacity(0.2))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartDateScrub(over: dataPoints, selection: $selectedIndex) { $0.date }
                    .frame(height: 220)

                    if let idx = selectedIndex, idx < dataPoints.count {
                        let point = dataPoints[idx]
                        let inRange = optimalRange.contains(point.wpm)
                        HStack(spacing: 12) {
                            Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                Text("\(Int(point.wpm))")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(inRange ? AppColors.success : AppColors.warning)
                                Text("WPM")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(inRange ? "In range" : (point.wpm > targetWPM ? "Too fast" : "Too slow"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(inRange ? AppColors.success : AppColors.warning)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    } else {
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(AppColors.primary.opacity(0.2)).frame(width: 14, height: 8)
                                Text("\(Int(optimalRange.lowerBound))-\(Int(optimalRange.upperBound)) optimal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Circle().fill(AppColors.categoryBrandBright).frame(width: 6, height: 6)
                                Text("Avg: \(Int(avgWPM))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    EmptyStateInline(
                        icon: "speedometer",
                        message: "Two sessions and this starts tracking your pace."
                    )
                }
            }
        }
    }
}

// MARK: - Subscore Radar View

struct SubscoreRadarView: View {
    let subscores: SpeechSubscores?

    @State private var animateBars = false

    private var latestSubscores: SpeechSubscores? { subscores }

    private struct RadarPoint: Identifiable {
        let label: String
        let value: Double
        let color: Color
        let icon: String

        var id: String { label }
    }

    private var radarPoints: [RadarPoint] {
        guard let s = latestSubscores else { return [] }
        return [
            RadarPoint(label: "Clarity", value: Double(s.clarity), color: AppColors.categoryTeal, icon: "waveform"),
            RadarPoint(label: "Pace", value: Double(s.pace), color: AppColors.categoryBrandBright, icon: "metronome"),
            RadarPoint(label: "Fillers", value: Double(s.fillerUsage), color: AppColors.warning, icon: "bubble.left.fill"),
            RadarPoint(label: "Pauses", value: Double(s.pauseQuality), color: AppColors.categoryIndigo, icon: "pause.circle.fill"),
            RadarPoint(label: "Vocal", value: Double(s.vocalVariety ?? 50), color: AppColors.categoryPlum, icon: "speaker.wave.3.fill"),
            RadarPoint(label: "Delivery", value: Double(s.delivery ?? 50), color: AppColors.error, icon: "person.fill"),
            RadarPoint(label: "Vocab", value: Double(s.vocabulary ?? 50), color: AppColors.success, icon: "character.book.closed"),
            RadarPoint(label: "Structure", value: Double(s.structure ?? 50), color: AppColors.warning, icon: "list.bullet"),
        ]
    }

    private var strongest: RadarPoint? {
        radarPoints.max(by: { $0.value < $1.value })
    }

    private var weakest: RadarPoint? {
        radarPoints.min(by: { $0.value < $1.value })
    }

    var body: some View {
        VStack(spacing: 12) {
            // Strongest / Weakest callout cards
            if let strong = strongest, let weak = weakest {
                HStack(spacing: 10) {
                    GlassCard(tint: strong.color.opacity(0.08), padding: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: strong.icon)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(strong.color)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Strongest")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Text(strong.label)
                                        .font(.caption.weight(.bold))
                                    Text("\(Int(strong.value))")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(strong.color)
                                }
                            }
                        }
                    }

                    GlassCard(tint: weak.color.opacity(0.08), padding: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: weak.icon)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(weak.color)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Focus Area")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Text(weak.label)
                                        .font(.caption.weight(.bold))
                                    Text("\(Int(weak.value))")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(weak.color)
                                }
                            }
                        }
                    }
                }
            }

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
                        VStack(spacing: 10) {
                            ForEach(radarPoints) { point in
                                HStack(spacing: 8) {
                                    Image(systemName: point.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(point.color)
                                        .frame(width: 16)

                                    Text(point.label)
                                        .font(.caption.weight(.medium))
                                        .frame(width: 56, alignment: .trailing)
                                        .foregroundStyle(.secondary)

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.08))

                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [point.color.opacity(0.4), point.color.opacity(0.8)],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: animateBars ? geo.size.width * (point.value / 100) : 0)
                                        }
                                    }
                                    .frame(height: 14)

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
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animateBars = true
            }
        }
    }
}

// MARK: - Session Frequency Chart

struct SessionFrequencyChart: View {
    let points: [ChartRecordingPoint]

    @Query private var userSettings: [UserSettings]
    @State private var selectedIndex: Int?

    private var weeklyGoal: Int {
        userSettings.first?.weeklyGoalSessions ?? 5
    }

    private var weeklyCounts: [(weekStart: Date, count: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { p in
            calendar.startOfDay(for: p.date.startOfWeek)
        }

        return grouped.map { (weekStart, recs) in
            (weekStart: weekStart, count: recs.count)
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    private var goalHitRate: Int {
        guard !weeklyCounts.isEmpty else { return 0 }
        let hit = weeklyCounts.filter { $0.count >= weeklyGoal }.count
        return Int(Double(hit) / Double(weeklyCounts.count) * 100)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Sessions per Week", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    if weeklyCounts.count >= 2 {
                        Text("\(goalHitRate)% goal hit")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(goalHitRate >= 70 ? AppColors.success : goalHitRate >= 40 ? AppColors.warning : AppColors.error)
                    }
                }

                if weeklyCounts.count >= 2 {
                    Chart {
                        RuleMark(y: .value("Goal", weeklyGoal))
                            .foregroundStyle(AppColors.primary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("Goal")
                                    .font(.system(size: 8))
                                    .foregroundStyle(AppColors.primary.opacity(0.6))
                            }

                        ForEach(Array(weeklyCounts.enumerated()), id: \.offset) { index, point in
                            BarMark(
                                x: .value("Week", point.weekStart, unit: .weekOfYear),
                                y: .value("Sessions", point.count)
                            )
                            .foregroundStyle(
                                selectedIndex == index
                                    ? (point.count >= weeklyGoal ? AppColors.primary : Color.white.opacity(0.5))
                                    : (point.count >= weeklyGoal ? AppColors.primary.opacity(0.7) : Color.white.opacity(0.25))
                            )
                            .cornerRadius(6)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartDateScrub(over: weeklyCounts, selection: $selectedIndex) { $0.weekStart }
                    .frame(height: 200)

                    if let idx = selectedIndex, idx < weeklyCounts.count {
                        let week = weeklyCounts[idx]
                        HStack(spacing: 12) {
                            Text("Week of \(week.weekStart.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            HStack(spacing: 4) {
                                Text("\(week.count)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(week.count >= weeklyGoal ? AppColors.primary : .primary)
                                Text("/ \(weeklyGoal)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if week.count >= weeklyGoal {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.success)
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    } else {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(AppColors.primary.opacity(0.7)).frame(width: 10, height: 10)
                                Text("Goal met")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.25)).frame(width: 10, height: 10)
                                Text("Below goal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    EmptyStateInline(
                        icon: "calendar",
                        message: "Practice across a couple of weeks to see your rhythm."
                    )
                }
            }
        }
    }
}

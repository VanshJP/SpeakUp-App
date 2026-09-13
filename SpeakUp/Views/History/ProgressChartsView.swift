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

/// Shared plot height for every Progress trend chart. One value, because a
/// tab switch that also resizes the well below it reads as layout jitter.
enum TrendChart {
    static let plotHeight: CGFloat = 210
}

struct ProgressChartsContent: View {
    @Environment(\.modelContext) private var modelContext

    var vocabWords: [VocabCount] = []

    @State private var points: [ChartRecordingPoint] = []
    @State private var latestSubscores: SpeechSubscores?
    @State private var scenarioCards: [ScenarioReadiness] = []
    @State private var isLoading = true

    @State private var selectedTab: ChartTab = .score
    @State private var timeRange: TimeRange = .thirtyDays
    @State private var lexiconProfile: LexiconProfile?
    @State private var heroRingShown = false

    enum ChartTab: String, CaseIterable, Identifiable {
        case score = "Score"
        case pace = "Pace"
        case fillers = "Fillers"
        case words = "Language"
        case skills = "Skills"
        case activity = "Activity"

        var id: String { rawValue }

        var usesTimeRange: Bool { self != .skills && self != .words }
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
        Group {
            if isLoading {
                loadingState
            } else if points.count < 2 {
                earlyState
            } else {
                VStack(spacing: 20) {
                    // Conclusion — where am I and which way am I moving.
                    heroBand

                    trendsSection

                    // Guidance — which situation needs work.
                    ScenarioReadinessSection(
                        cards: scenarioCards,
                        overallScore: lexiconProfile?.interviewReadiness?.score,
                        analyzedSessions: lexiconProfile?.analyzedSessionCount ?? 0
                    )
                }
            }
        }
        .task { await loadPoints() }
    }

    private var loadingState: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
    }

    private var earlyState: some View {
        EmptyStateCard(
            icon: "chart.line.uptrend.xyaxis",
            title: points.isEmpty ? "Your progress starts here" : "One take in",
            message: points.isEmpty
                ? "Record your first session. After two takes Big Talk maps where you stand and which way you are moving."
                : "One more recorded session and your trajectory, readiness map, and trend charts appear here."
        )
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader("Trends", icon: "chart.xyaxis.line") {
                Text("\(points.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    SectionPicker(
                        sections: ChartTab.allCases,
                        selection: $selectedTab,
                        label: { $0.rawValue },
                        layout: .equalWidth,
                        framed: false
                    )

                    timeRangeSlot
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionPicker(
                        sections: ChartTab.allCases,
                        selection: $selectedTab,
                        label: { $0.rawValue },
                        layout: .scrollable,
                        framed: false
                    )
                    .frame(maxWidth: .infinity)
                    .layoutPriority(0)

                    timeRangeSlot
                }
            }

            if selectedTab == .words {
                LanguageInsightsView(profile: lexiconProfile, vocabWords: vocabWords)
            } else if filteredPoints.isEmpty {
                GlassCard {
                    EmptyStateInline(
                        icon: "chart.line.uptrend.xyaxis",
                        message: points.isEmpty
                            ? "Complete a few recordings to see your progress trends."
                            : "No sessions in this window yet. Try widening the time range."
                    )
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
                    SkillBreakdownCard(subscores: latestSubscores, overallScore: points.first?.score ?? 0)
                case .activity:
                    SessionFrequencyChart(points: filteredPoints)
                case .words:
                    LanguageInsightsView(profile: lexiconProfile, vocabWords: vocabWords)
                }
            }
        }
    }

    private var timeRangeSlot: some View {
        timeRangeMenu
            .fixedSize()
            .opacity(selectedTab.usesTimeRange ? 1 : 0)
            .disabled(!selectedTab.usesTimeRange)
            .accessibilityHidden(!selectedTab.usesTimeRange)
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
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityLabel("Time range")
    }

    // MARK: - Background Load

    private func loadPoints() async {
        let container = modelContext.container
        let result = await Task.detached(priority: .userInitiated) { () -> ([ChartRecordingPoint], SpeechSubscores?, LexiconProfile, [ScenarioReadiness]) in
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            guard let recordings = try? context.fetch(descriptor) else {
                return ([], nil, .empty, [])
            }

            var pts: [ChartRecordingPoint] = []
            pts.reserveCapacity(recordings.count)
            var latest: SpeechSubscores?
            var sessions: [LexiconSessionInput] = []
            sessions.reserveCapacity(recordings.count)

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

                if let transcript = r.transcriptionText, !transcript.isEmpty {
                    var fillerCounts: [String: Int] = [:]
                    for filler in analysis.fillerWords where filler.count > 0 {
                        fillerCounts[filler.word.lowercased(), default: 0] += filler.count
                    }
                    sessions.append(LexiconSessionInput(
                        date: r.date,
                        transcript: transcript,
                        fillerCounts: fillerCounts,
                        overallScore: analysis.speechScore.overall,
                        category: r.storyId != nil ? ScenarioReadinessEngine.storyMarker : r.prompt?.category
                    ))
                }
            }

            let profile = LexiconInsightsEngine.profile(from: sessions)
            let scenarios = ScenarioReadinessEngine.readiness(from: sessions)
            return (pts, latest, profile, scenarios)
        }.value

        points = result.0
        latestSubscores = result.1
        lexiconProfile = result.2
        scenarioCards = result.3
        isLoading = false
    }

    // MARK: - Hero Band

    private var heroBand: some View {
        let trajectory = TrajectorySummary.summarize(points.reversed().map(\.score))
        let weekStart = Date().startOfWeek
        let thisWeek = points.filter { $0.date >= weekStart }.count
        let latest = trajectory.latestScore ?? 0

        return FeaturedGlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RingProgress(
                            progress: heroRingShown ? Double(latest) / 100 : 0,
                            color: AppColors.scoreColor(for: latest),
                            lineWidth: 6
                        )

                        Text("\(latest)")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    .frame(width: 58, height: 58)
                    .animation(AppMotion.reveal.delay(0.1), value: heroRingShown)
                    .onAppear { heroRingShown = true }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Where You Stand")
                            .eyebrowStyle()

                        trajectoryBadge(trajectory)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    heroCadence("\(trajectory.bestScore)", label: "Best", color: AppColors.warning)
                    cadenceDivider
                    heroCadence("\(trajectory.averageScore)", label: "Average", color: AppColors.primary)
                    cadenceDivider
                    heroCadence("\(thisWeek)", label: "This week", color: AppColors.success)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Where you stand: latest score \(latest) of 100, \(trajectory.momentum.label.lowercased()), best \(trajectory.bestScore), average \(trajectory.averageScore), \(thisWeek) sessions this week."
            )
        }
    }

    private func heroCadence(_ value: String, label: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.statValue)
                .monospacedDigit()
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var cadenceDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 18)
    }

    /// The hero's momentum pill, reading its symbol/word/tint from
    /// `ScenarioMomentum` so it can never disagree with the inline glyph the
    /// readiness rows use further down the same page.
    private func trajectoryBadge(_ trajectory: TrajectorySummary) -> some View {
        let momentum = trajectory.momentum

        return HStack(spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: momentum.symbolName)
                    .font(.caption2.weight(.bold))
                Text(momentum.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(momentum.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(momentum.tint.opacity(0.13)) }
            .overlay { Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5) }

            if momentum != .steady, trajectory.delta != 0 {
                Text("\(trajectory.delta > 0 ? "+" : "")\(trajectory.delta) pts")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(momentum.tint)
            }
        }
    }
}

// MARK: - Progress Charts View (standalone / navigation destination)

struct ProgressChartsView: View {
    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            PageScrollView {
                ProgressChartsContent()
                    .pageContentInsets()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Progress Charts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Score Progress Chart

struct ScoreProgressChart: View {
    @State private var selectedIndex: Int?

    /// Measured plot width, so the footer stats span exactly the shaded area
    /// and not the y-axis gutter. Measured rather than hardcoded because the
    /// gutter grows when the axis prints a three-digit score.
    @State private var plotWidth: CGFloat = 0

    /// Sorted points, trend line, and y-domain built once per `points` change.
    /// Scrubbing mutates `selectedIndex` on every frame and must not re-run
    /// any of this math in body.
    nonisolated private struct PlotModel {
        let points: [ChartRecordingPoint]
        let trend: [TrendPoint]
        let yDomain: ClosedRange<Int>
        let averageScore: Int
        let bestScore: Int

        nonisolated struct TrendPoint: Identifiable {
            let id: UUID
            let date: Date
            let score: Double
        }

        init(points source: [ChartRecordingPoint]) {
            let sorted = source.sorted { $0.date < $1.date }
            self.points = sorted

            var trend: [TrendPoint] = []
            if sorted.count >= 3 {
                for i in 1..<(sorted.count - 1) {
                    let avg = Double(sorted[i-1].score + sorted[i].score + sorted[i+1].score) / 3.0
                    trend.append(TrendPoint(id: sorted[i].id, date: sorted[i].date, score: avg))
                }
            }
            self.trend = trend

            let scores = sorted.map(\.score)
            yDomain = max(0, (scores.min() ?? 0) - 10)...min(100, (scores.max() ?? 100) + 10)
            averageScore = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
            bestScore = scores.max() ?? 0
        }
    }

    private let model: PlotModel

    init(points: [ChartRecordingPoint]) {
        _selectedIndex = State(initialValue: nil)
        model = PlotModel(points: points)
    }

    private var selectedPointID: UUID? {
        guard let selectedIndex, selectedIndex < model.points.count else { return nil }
        return model.points[selectedIndex].id
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Overall Score", icon: "chart.xyaxis.line") {
                    if model.points.count >= 3 {
                        HStack(spacing: 4) {
                            Circle().fill(AppColors.primary.opacity(0.4)).frame(width: 6, height: 6)
                            Text("Trend")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if model.points.count >= 2 {
                    Chart {
                        ForEach(model.points) { point in
                            // `yStart` is the domain floor, not the implicit 0.
                            // An AreaMark with only `y:` fills down to zero in
                            // *data* space, and this domain starts at
                            // `min - 10`, so the gradient used to run far below
                            // the plot and spill out the bottom of the card.
                            AreaMark(
                                x: .value("Date", point.date),
                                yStart: .value("Baseline", model.yDomain.lowerBound),
                                yEnd: .value("Score", point.score)
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

                        ForEach(model.points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(AppColors.primary)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(model.trend) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Trend", point.score),
                                series: .value("Series", "Trend")
                            )
                            .foregroundStyle(AppColors.primary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(model.points) { point in
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.score)
                            )
                            .foregroundStyle(
                                selectedPointID == point.id
                                    ? AppColors.scoreColor(for: point.score)
                                    : AppColors.primary
                            )
                            .symbolSize(selectedPointID == point.id ? 60 : 24)
                        }

                        if let idx = selectedIndex, idx < model.points.count {
                            RuleMark(x: .value("Selected", model.points[idx].date))
                                .foregroundStyle(.white.opacity(0.2))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYScale(domain: model.yDomain)
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
                    .chartPlotStyle { plot in
                        plot.background {
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.size.width, initial: true) { _, width in
                                        plotWidth = width
                                    }
                            }
                        }
                    }
                    .chartDateScrub(over: model.points, selection: $selectedIndex) { $0.date }
                    .frame(height: TrendChart.plotHeight)
                    .accessibilityLabel(
                        "Overall score over time, \(model.points.count) sessions, latest \(model.points.last?.score ?? 0), best \(model.bestScore)."
                    )

                    if let idx = selectedIndex, idx < model.points.count {
                        let point = model.points[idx]
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
                                let delta = point.score - model.points[idx - 1].score
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
                    } else if !model.points.isEmpty {
                        HStack(spacing: 16) {
                            StatPair(value: "\(model.points.last?.score ?? 0)", label: "Latest", valueColor: AppColors.scoreColor(for: model.points.last?.score ?? 0), alignment: .leading)
                            Spacer(minLength: 0)
                            StatPair(value: "\(model.averageScore)", label: "Average", valueColor: AppColors.primary)
                            Spacer(minLength: 0)
                            StatPair(value: "\(model.bestScore)", label: "Best", valueColor: AppColors.warning, alignment: .trailing)
                        }
                        .frame(width: plotWidth > 0 ? plotWidth : nil, alignment: .leading)
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

}

// MARK: - Weekly Bucket

nonisolated struct WeeklyBucket: Identifiable {
    let id: Date
    let avgFillers: Double
    let sessionCount: Int
}

// MARK: - Filler Trend Chart

struct FillerTrendChart: View {
    let points: [ChartRecordingPoint]

    @State private var selectedIndex: Int?

    private var weeklyData: [WeeklyBucket] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { p in
            calendar.startOfDay(for: p.date.startOfWeek)
        }

        return grouped.map { (weekStart, recs) in
            let totalFillers = recs.map(\.fillerCount).reduce(0, +)
            let avg = recs.isEmpty ? 0 : Double(totalFillers) / Double(recs.count)
            return WeeklyBucket(id: weekStart, avgFillers: avg, sessionCount: recs.count)
        }
        .sorted { $0.id < $1.id }
    }

    private var overallTrend: Double {
        guard weeklyData.count >= 2 else { return 0 }
        return weeklyData.last!.avgFillers - weeklyData.first!.avgFillers
    }

    private var selectedBucketID: Date? {
        guard let selectedIndex, selectedIndex < weeklyData.count else { return nil }
        return weeklyData[selectedIndex].id
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Filler Words per Session", icon: "exclamationmark.bubble.fill") {
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
                        ForEach(weeklyData) { point in
                            BarMark(
                                x: .value("Week", point.id, unit: .weekOfYear),
                                y: .value("Avg Fillers", point.avgFillers)
                            )
                            .foregroundStyle(
                                selectedBucketID == point.id
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
                    .chartDateScrub(over: weeklyData, selection: $selectedIndex) { $0.id }
                    .frame(height: TrendChart.plotHeight)
                    .accessibilityLabel(
                        "Average filler words per session by week, \(weeklyData.count) weeks, latest \(String(format: "%.1f", weeklyData.last?.avgFillers ?? 0))."
                    )

                    if let idx = selectedIndex, idx < weeklyData.count {
                        let week = weeklyData[idx]
                        HStack(spacing: 12) {
                            Text(week.id.formatted(.dateTime.month(.abbreviated).day()))
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
    @Query private var userSettings: [UserSettings]
    @State private var selectedIndex: Int?

    nonisolated private struct PlotModel {
        let points: [PlotPoint]
        let yDomain: ClosedRange<Double>
        let avgWPM: Double

        nonisolated struct PlotPoint: Identifiable {
            let id: UUID
            let date: Date
            let wpm: Double
        }

        init(points source: [ChartRecordingPoint]) {
            self.points = source.compactMap { p in
                p.wpm > 0 ? PlotPoint(id: p.id, date: p.date, wpm: p.wpm) : nil
            }
            .sorted { $0.date < $1.date }

            let wpms = points.map(\.wpm)
            yDomain = max(60, (wpms.min() ?? 100) - 20)...min(250, (wpms.max() ?? 200) + 20)
            avgWPM = wpms.isEmpty ? 0 : wpms.reduce(0, +) / Double(wpms.count)
        }
    }

    private let model: PlotModel

    init(points: [ChartRecordingPoint]) {
        _userSettings = Query()
        _selectedIndex = State(initialValue: nil)
        model = PlotModel(points: points)
    }

    private var targetWPM: Double {
        Double(userSettings.first.resolvedTargetWPM)
    }

    private var optimalRange: ClosedRange<Double> {
        (targetWPM - 10)...(targetWPM + 10)
    }

    private var selectedPointID: UUID? {
        guard let selectedIndex, selectedIndex < model.points.count else { return nil }
        return model.points[selectedIndex].id
    }

    private var inRangePercent: Int {
        guard !model.points.isEmpty else { return 0 }
        let inRange = model.points.filter { optimalRange.contains($0.wpm) }.count
        return Int(Double(inRange) / Double(model.points.count) * 100)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Pace (WPM)", icon: "metronome") {
                    Text("\(inRangePercent)% in range")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(inRangePercent >= 70 ? AppColors.success : inRangePercent >= 40 ? AppColors.warning : AppColors.error)
                }

                if model.points.count >= 2 {
                    Chart {
                        RectangleMark(
                            yStart: .value("Low", optimalRange.lowerBound),
                            yEnd: .value("High", optimalRange.upperBound)
                        )
                        .foregroundStyle(AppColors.primary.opacity(0.08))

                        RuleMark(y: .value("Target", targetWPM))
                            .foregroundStyle(AppColors.primary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("Target")
                                    .font(.system(size: 8))
                                    .foregroundStyle(AppColors.primary.opacity(0.6))
                            }

                        ForEach(model.points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("WPM", point.wpm)
                            )
                            .foregroundStyle(AppColors.categoryBrandBright)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(model.points) { point in
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("WPM", point.wpm)
                            )
                            .foregroundStyle(
                                optimalRange.contains(point.wpm)
                                    ? AppColors.success
                                    : AppColors.warning
                            )
                            .symbolSize(selectedPointID == point.id ? 60 : 24)
                        }

                        if let idx = selectedIndex, idx < model.points.count {
                            RuleMark(x: .value("Selected", model.points[idx].date))
                                .foregroundStyle(.white.opacity(0.2))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYScale(domain: model.yDomain)
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
                    .chartDateScrub(over: model.points, selection: $selectedIndex) { $0.date }
                    .frame(height: TrendChart.plotHeight)
                    .accessibilityLabel(
                        "Speaking pace over time, \(model.points.count) sessions, \(inRangePercent) percent within target range."
                    )

                    if let idx = selectedIndex, idx < model.points.count {
                        let point = model.points[idx]
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
                                Text("Avg: \(Int(model.avgWPM))")
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

// MARK: - Skill Breakdown Card

struct SkillBreakdownCard: View {
    let subscores: SpeechSubscores?
    let overallScore: Int

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Skill Breakdown", icon: "star.fill") {
                    Text("Latest take")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let s = subscores {
                    let axes = SubscoreRadarChart.Axis.from(subscores: s, isPromptRelevance: false)

                    SubscoreRadarChart(
                        axes: axes,
                        overallScore: overallScore,
                        emphasizedAxisIDs: SubscoreRadarChart.Axis.emphasisIDs(in: axes)
                    )
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)

                    Text("Tap a segment to see what it measures.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    EmptyStateInline(icon: "star.fill", message: "No analysis data available")
                }
            }
        }
    }
}

// MARK: - Session Frequency Chart

nonisolated private struct WeeklyFrequencyBucket: Identifiable {
    let id: Date
    let sessionCount: Int
}

struct SessionFrequencyChart: View {
    let points: [ChartRecordingPoint]

    @Query private var userSettings: [UserSettings]
    @State private var selectedIndex: Int?

    private var weeklyGoal: Int {
        userSettings.first?.weeklyGoalSessions ?? 5
    }

    private var weeklyCounts: [WeeklyFrequencyBucket] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { p in
            calendar.startOfDay(for: p.date.startOfWeek)
        }

        return grouped.map { (weekStart, recs) in
            WeeklyFrequencyBucket(id: weekStart, sessionCount: recs.count)
        }
        .sorted { $0.id < $1.id }
    }

    private var goalHitRate: Int {
        guard !weeklyCounts.isEmpty else { return 0 }
        let hit = weeklyCounts.filter { $0.sessionCount >= weeklyGoal }.count
        return Int(Double(hit) / Double(weeklyCounts.count) * 100)
    }

    private var selectedWeekID: Date? {
        guard let selectedIndex, selectedIndex < weeklyCounts.count else { return nil }
        return weeklyCounts[selectedIndex].id
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Sessions per Week", icon: "calendar") {
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

                        ForEach(weeklyCounts) { point in
                            BarMark(
                                x: .value("Week", point.id, unit: .weekOfYear),
                                y: .value("Sessions", point.sessionCount)
                            )
                            .foregroundStyle(
                                selectedWeekID == point.id
                                    ? (point.sessionCount >= weeklyGoal ? AppColors.primary : Color.white.opacity(0.5))
                                    : (point.sessionCount >= weeklyGoal ? AppColors.primary.opacity(0.7) : Color.white.opacity(0.25))
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
                    .chartDateScrub(over: weeklyCounts, selection: $selectedIndex) { $0.id }
                    .frame(height: TrendChart.plotHeight)
                    .accessibilityLabel(
                        "Sessions per week, \(weeklyCounts.count) weeks, \(goalHitRate) percent of weeks hit the goal."
                    )

                    if let idx = selectedIndex, idx < weeklyCounts.count {
                        let week = weeklyCounts[idx]
                        HStack(spacing: 12) {
                            Text("Week of \(week.id.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            HStack(spacing: 4) {
                                Text("\(week.sessionCount)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(week.sessionCount >= weeklyGoal ? AppColors.primary : .primary)
                                Text("/ \(weeklyGoal)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if week.sessionCount >= weeklyGoal {
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

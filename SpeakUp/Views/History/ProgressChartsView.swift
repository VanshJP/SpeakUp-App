import SwiftUI
import SwiftData
import Charts

struct ProgressChartsView: View {
    @Query(sort: \Recording.date, order: .reverse) private var recordings: [Recording]

    @State private var selectedTab: ChartTab = .score
    @State private var timeRange: TimeRange = .thirtyDays

    enum ChartTab: String, CaseIterable {
        case score = "Score"
        case fillers = "Fillers"
        case pace = "Pace"
        case skills = "Skills"
        case activity = "Activity"

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

    private var allAnalyzedRecordings: [Recording] {
        recordings.filter { $0.analysis != nil }
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            ScrollView {
                VStack(spacing: 20) {
                    // Highlights hero section
                    if allAnalyzedRecordings.count >= 2 {
                        highlightsSection
                    }

                    // Tab picker
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(ChartTab.allCases, id: \.self) { tab in
                                Button {
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedTab = tab
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: tab.icon)
                                            .font(.caption2)
                                        Text(tab.rawValue)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background {
                                        Capsule()
                                            .fill(selectedTab == tab
                                                  ? LinearGradient(colors: [.teal.opacity(0.8), .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                  : LinearGradient(colors: [Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                                    }
                                    .overlay {
                                        if selectedTab == tab {
                                            Capsule()
                                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    // Time range picker (not for skills)
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

    // MARK: - Highlights Section

    private var highlightsSection: some View {
        let sorted = allAnalyzedRecordings.sorted { $0.date < $1.date }
        let scores = sorted.compactMap { $0.analysis?.speechScore.overall }
        let bestScore = scores.max() ?? 0
        let latestScore = scores.last ?? 0
        let firstScore = scores.first ?? 0
        let totalImprovement = latestScore - firstScore

        // Find best subscore
        let latestSubscores = sorted.last?.analysis?.speechScore.subscores
        let bestSubscore = bestSubscoreInfo(from: latestSubscores)

        return VStack(spacing: 12) {
            // Hero highlight card
            FeaturedGlassCard(gradientColors: [
                (totalImprovement >= 0 ? Color.teal : Color.orange).opacity(0.12),
                .cyan.opacity(0.05)
            ]) {
                HStack(spacing: 16) {
                    // Left: big number
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Journey")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(latestScore)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.scoreColor(for: latestScore))

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
                            .foregroundStyle(totalImprovement > 0 ? .green : .red)
                        }
                    }

                    Spacer()

                    // Right: personal best badge
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(.yellow.opacity(0.15))
                                .frame(width: 52, height: 52)

                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow)
                        }

                        Text("\(bestScore)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.yellow)

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
                    value: "\(allAnalyzedRecordings.count)",
                    color: .teal
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
            return SubscoreInfo(name: "—", icon: "star.fill", color: .teal)
        }

        let all: [(String, Int, String, Color)] = [
            ("Clarity", s.clarity, "waveform", .blue),
            ("Pace", s.pace, "metronome", .cyan),
            ("Fillers", s.fillerUsage, "bubble.left.fill", .orange),
            ("Pauses", s.pauseQuality, "pause.circle.fill", .purple),
            ("Vocal", s.vocalVariety ?? 0, "speaker.wave.3.fill", .pink),
            ("Delivery", s.delivery ?? 0, "person.fill", .red),
            ("Vocab", s.vocabulary ?? 0, "character.book.closed", .green),
            ("Structure", s.structure ?? 0, "list.bullet", .yellow),
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

// MARK: - Highlight Stat Card

private struct HighlightStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        GlassCard(tint: color.opacity(0.06), padding: 12) {
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
    let recordings: [Recording]

    @State private var selectedIndex: Int?

    private var dataPoints: [(date: Date, score: Int, id: UUID)] {
        recordings
            .compactMap { r in
                guard let score = r.analysis?.speechScore.overall else { return nil }
                return (date: r.date, score: score, id: r.id)
            }
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
                            Circle().fill(.teal.opacity(0.4)).frame(width: 6, height: 6)
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
                                    colors: [.teal.opacity(0.25), .teal.opacity(0.02)],
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
                            .foregroundStyle(.teal)
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
                            .foregroundStyle(.teal.opacity(0.35))
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
                                    : .teal
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
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPos = value.location.x
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let origin = geometry[plotFrame].origin.x
                                            let relX = xPos - origin
                                            guard let date: Date = proxy.value(atX: relX) else { return }

                                            // Find nearest data point
                                            var closestIdx = 0
                                            var closestDist = Double.infinity
                                            for (i, dp) in dataPoints.enumerated() {
                                                let dist = abs(dp.date.timeIntervalSince(date))
                                                if dist < closestDist {
                                                    closestDist = dist
                                                    closestIdx = i
                                                }
                                            }
                                            selectedIndex = closestIdx
                                            Haptics.selection()
                                        }
                                        .onEnded { _ in
                                            selectedIndex = nil
                                        }
                                )
                        }
                    }
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
                                .foregroundStyle(delta >= 0 ? .green : .red)
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    } else if !dataPoints.isEmpty {
                        HStack(spacing: 16) {
                            chartStat("Latest", value: "\(dataPoints.last?.score ?? 0)", color: AppColors.scoreColor(for: dataPoints.last?.score ?? 0))
                            chartStat("Average", value: "\(dataPoints.map(\.score).reduce(0, +) / dataPoints.count)", color: .teal)
                            chartStat("Best", value: "\(dataPoints.map(\.score).max() ?? 0)", color: .yellow)
                        }
                    }
                } else {
                    Text("Need at least 2 recordings to show trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
    }

    private func chartStat(_ label: String, value: String, color: Color = .teal) -> some View {
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
    let recordings: [Recording]

    @State private var selectedIndex: Int?

    private var weeklyData: [(weekStart: Date, avgFillers: Double, sessionCount: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recordings) { r in
            calendar.startOfDay(for: r.date.startOfWeek)
        }

        return grouped.map { (weekStart, recs) in
            let totalFillers = recs.compactMap { $0.analysis?.totalFillerCount }.reduce(0, +)
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
                        .foregroundStyle(overallTrend < -1 ? .green : overallTrend > 1 ? .orange : .secondary)
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
                                    ? (point.avgFillers > 10 ? Color.red : point.avgFillers > 5 ? Color.orange : Color.green)
                                    : (point.avgFillers > 10 ? Color.red.opacity(0.6) : point.avgFillers > 5 ? Color.orange.opacity(0.6) : Color.green.opacity(0.6))
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
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPos = value.location.x
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let origin = geometry[plotFrame].origin.x
                                            let relX = xPos - origin
                                            guard let date: Date = proxy.value(atX: relX) else { return }

                                            var closestIdx = 0
                                            var closestDist = Double.infinity
                                            for (i, dp) in weeklyData.enumerated() {
                                                let dist = abs(dp.weekStart.timeIntervalSince(date))
                                                if dist < closestDist {
                                                    closestDist = dist
                                                    closestIdx = i
                                                }
                                            }
                                            if selectedIndex != closestIdx {
                                                selectedIndex = closestIdx
                                                Haptics.selection()
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedIndex = nil
                                        }
                                )
                        }
                    }
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
                                    .foregroundStyle(week.avgFillers > 10 ? .red : week.avgFillers > 5 ? .orange : .green)
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
                            fillerLegendItem(color: .green, label: "0-5")
                            fillerLegendItem(color: .orange, label: "5-10")
                            fillerLegendItem(color: .red, label: "10+")
                        }
                    }
                } else {
                    Text("Need more recordings across different weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
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
    let recordings: [Recording]

    @Query private var userSettings: [UserSettings]
    @State private var selectedIndex: Int?

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
                        .foregroundStyle(inRangePercent >= 70 ? .green : inRangePercent >= 40 ? .orange : .red)
                }

                if dataPoints.count >= 2 {
                    Chart {
                        // Optimal range band
                        RectangleMark(
                            yStart: .value("Low", optimalRange.lowerBound),
                            yEnd: .value("High", optimalRange.upperBound)
                        )
                        .foregroundStyle(.teal.opacity(0.08))

                        // Target line
                        RuleMark(y: .value("Target", targetWPM))
                            .foregroundStyle(.teal.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("Target")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.teal.opacity(0.6))
                            }

                        // Line
                        ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("WPM", point.wpm)
                            )
                            .foregroundStyle(.cyan)
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
                                    ? .green
                                    : (point.wpm > optimalRange.upperBound ? .orange : .orange)
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
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPos = value.location.x
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let origin = geometry[plotFrame].origin.x
                                            let relX = xPos - origin
                                            guard let date: Date = proxy.value(atX: relX) else { return }

                                            var closestIdx = 0
                                            var closestDist = Double.infinity
                                            for (i, dp) in dataPoints.enumerated() {
                                                let dist = abs(dp.date.timeIntervalSince(date))
                                                if dist < closestDist {
                                                    closestDist = dist
                                                    closestIdx = i
                                                }
                                            }
                                            if selectedIndex != closestIdx {
                                                selectedIndex = closestIdx
                                                Haptics.selection()
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedIndex = nil
                                        }
                                )
                        }
                    }
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
                                    .foregroundStyle(inRange ? .green : .orange)
                                Text("WPM")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(inRange ? "In range" : (point.wpm > targetWPM ? "Too fast" : "Too slow"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(inRange ? .green : .orange)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    } else {
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(.teal.opacity(0.2)).frame(width: 14, height: 8)
                                Text("\(Int(optimalRange.lowerBound))-\(Int(optimalRange.upperBound)) optimal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Circle().fill(.cyan).frame(width: 6, height: 6)
                                Text("Avg: \(Int(avgWPM))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
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

    @State private var animateBars = false

    private var latestSubscores: SpeechSubscores? {
        recordings.first(where: { $0.analysis != nil })?.analysis?.speechScore.subscores
    }

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
            RadarPoint(label: "Clarity", value: Double(s.clarity), color: .blue, icon: "waveform"),
            RadarPoint(label: "Pace", value: Double(s.pace), color: .cyan, icon: "metronome"),
            RadarPoint(label: "Fillers", value: Double(s.fillerUsage), color: .orange, icon: "bubble.left.fill"),
            RadarPoint(label: "Pauses", value: Double(s.pauseQuality), color: .purple, icon: "pause.circle.fill"),
            RadarPoint(label: "Vocal", value: Double(s.vocalVariety ?? 50), color: .pink, icon: "speaker.wave.3.fill"),
            RadarPoint(label: "Delivery", value: Double(s.delivery ?? 50), color: .red, icon: "person.fill"),
            RadarPoint(label: "Vocab", value: Double(s.vocabulary ?? 50), color: .green, icon: "character.book.closed"),
            RadarPoint(label: "Structure", value: Double(s.structure ?? 50), color: .yellow, icon: "list.bullet"),
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
    let recordings: [Recording]

    @Query private var userSettings: [UserSettings]
    @State private var selectedIndex: Int?

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
                            .foregroundStyle(goalHitRate >= 70 ? .green : goalHitRate >= 40 ? .orange : .red)
                    }
                }

                if weeklyCounts.count >= 2 {
                    Chart {
                        RuleMark(y: .value("Goal", weeklyGoal))
                            .foregroundStyle(.teal.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("Goal")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.teal.opacity(0.6))
                            }

                        ForEach(Array(weeklyCounts.enumerated()), id: \.offset) { index, point in
                            BarMark(
                                x: .value("Week", point.weekStart, unit: .weekOfYear),
                                y: .value("Sessions", point.count)
                            )
                            .foregroundStyle(
                                selectedIndex == index
                                    ? (point.count >= weeklyGoal ? Color.teal : Color.white.opacity(0.5))
                                    : (point.count >= weeklyGoal ? Color.teal.opacity(0.7) : Color.white.opacity(0.25))
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
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPos = value.location.x
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let origin = geometry[plotFrame].origin.x
                                            let relX = xPos - origin
                                            guard let date: Date = proxy.value(atX: relX) else { return }

                                            var closestIdx = 0
                                            var closestDist = Double.infinity
                                            for (i, dp) in weeklyCounts.enumerated() {
                                                let dist = abs(dp.weekStart.timeIntervalSince(date))
                                                if dist < closestDist {
                                                    closestDist = dist
                                                    closestIdx = i
                                                }
                                            }
                                            if selectedIndex != closestIdx {
                                                selectedIndex = closestIdx
                                                Haptics.selection()
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedIndex = nil
                                        }
                                )
                        }
                    }
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
                                    .foregroundStyle(week.count >= weeklyGoal ? .teal : .primary)
                                Text("/ \(weeklyGoal)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if week.count >= weeklyGoal {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    } else {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(.teal.opacity(0.7)).frame(width: 10, height: 10)
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
                    Text("Need more recording weeks to show frequency trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
    }
}

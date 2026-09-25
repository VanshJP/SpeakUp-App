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

// MARK: - Progress Charts Model

/// What the Progress page loaded, plus the tab and window the user picked.
/// It lives with whoever shows the page, not inside `ProgressChartsContent`:
/// History's Recordings / Progress picker tears the section down, and with
/// this state inside it every flip reset the tab to Score and the window to
/// 30 days, flashed the loader, and decoded every analysis again.
@MainActor @Observable
final class ProgressChartsModel {
    var selectedTab: ProgressChartsContent.ChartTab = .score
    var timeRange: ProgressChartsContent.TimeRange = .thirtyDays

    private(set) var points: [ChartRecordingPoint] = []
    private(set) var latestSubscores: SpeechSubscores?
    private(set) var scenarioCards: [ScenarioReadiness] = []
    private(set) var lexiconProfile: LexiconProfile?
    /// False until the first pass lands. Later passes (one per appearance, so
    /// a new take shows up) refresh in place behind the charts already drawn.
    private(set) var hasLoaded = false
    /// The opening window is picked once, when there is first a trend to show.
    @ObservationIgnored private var rangeSettled = false
    /// What the last pass was loaded for (see `load(from:key:)`).
    @ObservationIgnored private var loadedKey: Int?

    /// One background pass: every analyzed take becomes a chart point and a
    /// lexicon input, so chart bodies never decode an analysis blob.
    ///
    /// `key` fingerprints the takes behind the page; a pass for the key
    /// already loaded is skipped, so returning to the page does not decode
    /// every analysis again. Nil always loads (pull-to-refresh, Today's push).
    func load(from container: ModelContainer, key: Int? = nil) async {
        if hasLoaded, let key, key == loadedKey { return }

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

        // The page went away mid-pass; the next appearance loads again.
        guard !Task.isCancelled else { return }

        points = result.0
        latestSubscores = result.1
        lexiconProfile = result.2
        scenarioCards = result.3
        hasLoaded = true
        loadedKey = key

        if !rangeSettled, result.0.count >= 2 {
            timeRange = .opening(for: result.0)
            rangeSettled = true
        }
    }
}

// MARK: - Progress Charts Content

struct ProgressChartsContent: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var model: ProgressChartsModel
    var vocabWords: [VocabCount] = []
    /// The early state's way out. Nil when Today pushed the page: Today is
    /// one Back away.
    var onShowToday: (() -> Void)? = nil
    /// Opens a take from a pinned Score or Pace point. Nil hides that action.
    var onSelectRecording: ((String) -> Void)? = nil
    /// Starts practice for a readiness row. Nil keeps the rows read-only.
    var onPracticeScenario: ((PracticeScenario) -> Void)? = nil
    /// Fingerprint of the takes behind the page; the charts reload when it
    /// changes. Nil reloads on every appearance.
    var reloadKey: Int? = nil

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

        /// Start of the window, or nil for all time.
        func cutoff(from now: Date = .now) -> Date? {
            days.map { now.addingTimeInterval(-Double($0) * 86400) }
        }

        /// The window the page opens on: 30 days, widened until it holds the
        /// two takes a trend needs, so someone back after a month away does
        /// not open onto an empty plot.
        static func opening(for points: [ChartRecordingPoint]) -> TimeRange {
            let now = Date.now
            for range in [TimeRange.thirtyDays, .ninetyDays] {
                guard let cutoff = range.cutoff(from: now) else { continue }
                if points.filter({ $0.date >= cutoff }).count >= 2 { return range }
            }
            return .all
        }
    }

    private var filteredPoints: [ChartRecordingPoint] {
        guard let cutoff = model.timeRange.cutoff() else { return model.points }
        return model.points.filter { $0.date >= cutoff }
    }

    var body: some View {
        Group {
            if !model.hasLoaded {
                loadingState
            } else if model.points.count < 2 {
                earlyState
            } else {
                VStack(spacing: 20) {
                    // Conclusion - where am I and which way am I moving.
                    heroBand

                    trendsSection

                    // Guidance - which situation needs work.
                    ScenarioReadinessSection(
                        cards: model.scenarioCards,
                        overallScore: model.lexiconProfile?.interviewReadiness?.score,
                        analyzedSessions: model.lexiconProfile?.analyzedSessionCount ?? 0,
                        onPractice: onPracticeScenario
                    )
                }
            }
        }
        .task(id: reloadKey) { await model.load(from: modelContext.container, key: reloadKey) }
    }

    private var loadingState: some View {
        VoiceLoader(size: .large)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
    }

    private var earlyState: some View {
        EmptyStateCard(
            icon: "chart.line.uptrend.xyaxis",
            title: model.points.isEmpty ? "Your progress starts here" : "One take in",
            message: model.points.isEmpty
                // Counts scored takes only - "record your first session"
                // was wrong for anyone whose only take had not scored.
                ? "After two scored takes, Big Talk maps where you stand and which way you are moving."
                : "One more recorded session and your trajectory, readiness map, and trend charts appear here.",
            // The same destination and words as the empty Recordings list.
            buttonTitle: onShowToday == nil ? nil : "Choose today's prompt",
            buttonAction: onShowToday
        )
    }

    private var trendsSection: some View {
        let windowPoints = filteredPoints
        let usesRange = model.selectedTab.usesTimeRange

        return VStack(alignment: .leading, spacing: 12) {
            // The window belongs to the chapter, not the tab row: beside six
            // tabs it overflowed a phone's width and pushed the row onto a
            // scrolling rail with Activity off-screen.
            GlassSectionHeader("Trends") {
                HStack(spacing: 8) {
                    Text(windowPoints.count == 1 ? "1 session" : "\(windowPoints.count) sessions")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    timeRangeMenu
                }
                // Held in the layout while hidden so a tab switch never moves the plot.
                .opacity(usesRange ? 1 : 0)
                .disabled(!usesRange)
                .accessibilityHidden(!usesRange)
            }

            ViewThatFits(in: .horizontal) {
                chartTabPicker(layout: .equalWidth)

                chartTabPicker(layout: .scrollable)
                    .frame(maxWidth: .infinity)
            }

            chart(for: model.selectedTab, windowPoints: windowPoints)
        }
    }

    private func chartTabPicker(layout: SectionPicker<ChartTab>.Layout) -> some View {
        SectionPicker(
            sections: ChartTab.allCases,
            selection: $model.selectedTab,
            label: { $0.rawValue },
            layout: layout,
            framed: false
        )
    }

    /// Skills and Language ignore the window, so they never pass through its
    /// empty check: Skills used to say "try widening the time range" while
    /// the range control was hidden for that very tab.
    @ViewBuilder
    private func chart(for tab: ChartTab, windowPoints: [ChartRecordingPoint]) -> some View {
        switch tab {
        case .words:
            LanguageInsightsView(profile: model.lexiconProfile, vocabWords: vocabWords)
        case .skills:
            SkillBreakdownCard(subscores: model.latestSubscores, overallScore: model.points.first?.score ?? 0)
        case .score, .pace, .fillers, .activity:
            if let message = thinWindowMessage(for: tab, windowPoints: windowPoints) {
                thinWindowCard(message)
            } else if tab == .score {
                ScoreProgressChart(points: windowPoints, onOpenTake: openTake)
            } else if tab == .pace {
                PaceTrendChart(points: windowPoints, onOpenTake: openTake)
            } else if tab == .fillers {
                FillerTrendChart(points: windowPoints)
            } else {
                SessionFrequencyChart(points: windowPoints)
            }
        }
    }

    /// Why the window cannot draw this tab, or nil when it can. Per-take
    /// plots need two takes; Fillers and Activity compare weeks, so they need
    /// two weeks. This page only shows with two scored takes overall, so the
    /// charts' own "two sessions and this starts…" lines were wrong here.
    private func thinWindowMessage(for tab: ChartTab, windowPoints: [ChartRecordingPoint]) -> String? {
        let window = model.timeRange.menuLabel.lowercased()
        if windowPoints.isEmpty { return "No sessions in the \(window)." }

        switch tab {
        case .fillers, .activity:
            let weeks = Set(windowPoints.map { Calendar.current.startOfDay(for: $0.date.startOfWeek) })
            guard weeks.count < 2 else { return nil }
            return model.timeRange == .all
                ? "Weekly trends start after a second week of practice."
                : "Weekly trends need two weeks; the \(window) hold one."
        default:
            return windowPoints.count < 2 ? "One session in the \(window). A trend needs two." : nil
        }
    }

    private func thinWindowCard(_ message: String) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                EmptyStateInline(icon: "chart.line.uptrend.xyaxis", message: message)

                if model.timeRange != .all {
                    GlassButton(title: "Show all time", style: .secondary, size: .small) {
                        Haptics.selection()
                        model.timeRange = .all
                    }
                }
            }
        }
    }

    private var openTake: ((UUID) -> Void)? {
        guard let onSelectRecording else { return nil }
        return { onSelectRecording($0.uuidString) }
    }

    private var timeRangeMenu: some View {
        Menu {
            // A Picker gives the menu its own checkmark and the selected trait.
            Picker("Time range", selection: timeRangeSelection) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.menuLabel).tag(range)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.timeRange.rawValue)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: .capsule)
            // The hit target grows around the capsule, never under the glass.
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(.rect)
        }
        .accessibilityLabel("Time range")
        .accessibilityValue(model.timeRange.menuLabel)
    }

    private var timeRangeSelection: Binding<TimeRange> {
        Binding(
            get: { model.timeRange },
            set: { range in
                guard range != model.timeRange else { return }
                Haptics.selection()
                model.timeRange = range
            }
        )
    }

    // MARK: - Hero Band

    private var heroBand: some View {
        let trajectory = TrajectorySummary.summarize(model.points.reversed().map(\.score))
        let weekStart = Date().startOfWeek
        let thisWeek = model.points.filter { $0.date >= weekStart }.count
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

                        // Climbs with the ring - both ride `heroRingShown`.
                        CountUpText(
                            value: heroRingShown ? Double(latest) : 0,
                            font: .system(size: 21, weight: .bold, design: .rounded)
                        )
                    }
                    .frame(width: 58, height: 58)
                    .motion(AppMotion.reveal.delay(0.1), value: heroRingShown)
                    .onAppear { heroRingShown = true }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Where You Stand")
                            .eyebrowStyle()

                        trajectoryBadge(trajectory)
                    }

                    Spacer(minLength: 0)
                }

                // Scores wear the score ramp; amber and green mean caution and
                // success elsewhere on this page, not "best" and "this week".
                HStack(spacing: 0) {
                    heroCadence("\(trajectory.bestScore)", label: "Best", color: AppColors.scoreColor(for: trajectory.bestScore))
                    cadenceDivider
                    heroCadence("\(trajectory.averageScore)", label: "Average", color: AppColors.scoreColor(for: trajectory.averageScore))
                    cadenceDivider
                    heroCadence("\(thisWeek)", label: "This week", color: .white)
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

/// The page Today's rings push. It ends on the same Review tools as History's
/// Progress section; with no root callbacks here, it presents them itself.
struct ProgressChartsView: View {
    @State private var model = ProgressChartsModel()
    @State private var showingListenBack = false
    @State private var showingGoals = false
    @State private var showingJournal = false

    var body: some View {
        PageScrollView {
            VStack(spacing: AppLayout.chapterSpacing) {
                ProgressChartsContent(model: model)

                if model.hasLoaded {
                    ProgressReviewSection(
                        scoredTakes: model.points.count,
                        onListenBack: { showingListenBack = true },
                        onGoals: { showingGoals = true },
                        onJournal: { showingJournal = true }
                    )
                }
            }
            .pageContentInsets()
        }
        .scrollIndicators(.hidden)
        .appBackground(.subtle)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .restoresNavigationBar()
        .sheet(isPresented: $showingListenBack) {
            BeforeAfterReplayView()
        }
        .sheet(isPresented: $showingGoals) {
            GoalsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingJournal) {
            NavigationStack {
                JournalExportView()
            }
        }
    }
}

// MARK: - Review Section

/// Compare, Listen back, Goals and Journal under the Progress page - shared by
/// History's Progress section and the page Today's rings push, so both entry
/// points end on the same tools.
struct ProgressReviewSection: View {
    /// Compare and Listen back need two scored takes. Counting every take let
    /// a processing or failed one open them onto a zero score or an empty sheet.
    let scoredTakes: Int
    let onListenBack: () -> Void
    let onGoals: () -> Void
    let onJournal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Review")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(ReviewToolKind.allCases) { tool in
                    tile(tool)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ tool: ReviewToolKind) -> some View {
        switch tool {
        case .compare:
            if scoredTakes >= 2 {
                NavigationLink { ComparisonView().restoresNavigationBar() } label: {
                    ToolTileLabel(icon: tool.icon, title: tool.title, tint: tool.color)
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityHint(tool.bestFor)
            }
        case .listenBack:
            if scoredTakes >= 2 {
                tileButton(tool, action: onListenBack)
            }
        case .goals:
            tileButton(tool, action: onGoals)
        case .journal:
            tileButton(tool, action: onJournal)
        }
    }

    private func tileButton(_ tool: ReviewToolKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ToolTileLabel(icon: tool.icon, title: tool.title, tint: tool.color)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityHint(tool.bestFor)
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
    private let onOpenTake: ((UUID) -> Void)?

    init(points: [ChartRecordingPoint], onOpenTake: ((UUID) -> Void)? = nil) {
        _selectedIndex = State(initialValue: nil)
        model = PlotModel(points: points)
        self.onOpenTake = onOpenTake
    }

    private var selectedPointID: UUID? {
        guard let selectedIndex, selectedIndex < model.points.count else { return nil }
        return model.points[selectedIndex].id
    }

    private func openAction(for id: UUID) -> (() -> Void)? {
        guard let onOpenTake else { return nil }
        return { onOpenTake(id) }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Overall score", icon: "chart.xyaxis.line") {
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
                        ScrubReadout(onOpen: openAction(for: point.id)) {
                            HStack(spacing: 12) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(AppColors.scoreColor(for: point.score))
                                        .frame(width: 8, height: 8)
                                    Text("\(point.score)")
                                        .font(.headline.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(AppColors.scoreColor(for: point.score))
                                }

                                Text(point.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                if idx > 0 {
                                    let delta = point.score - model.points[idx - 1].score
                                    HStack(spacing: 3) {
                                        Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "arrow.right")
                                            .font(.caption2.weight(.bold))
                                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                                            .font(.caption.weight(.bold))
                                            .monospacedDigit()
                                    }
                                    // A drop is amber, never red - the page's one
                                    // colour for slipping.
                                    .foregroundStyle(delta > 0 ? AppColors.success : delta < 0 ? AppColors.warning : .secondary)
                                }
                            }
                        }
                        .transition(.opacity)
                    } else if !model.points.isEmpty {
                        HStack(spacing: 16) {
                            StatPair(value: "\(model.points.last?.score ?? 0)", label: "Latest", valueColor: AppColors.scoreColor(for: model.points.last?.score ?? 0), alignment: .leading)
                            Spacer(minLength: 0)
                            StatPair(value: "\(model.averageScore)", label: "Average", valueColor: AppColors.scoreColor(for: model.averageScore))
                            Spacer(minLength: 0)
                            StatPair(value: "\(model.bestScore)", label: "Best", valueColor: AppColors.scoreColor(for: model.bestScore), alignment: .trailing)
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

// MARK: - Scrub Readout

/// A pinned point's readout under a per-take plot. Given `onOpen` it is the
/// way into that take - a row that presses and ends in a chevron - which is
/// what History's charts owe: a point you can see but not open was a dead end.
private struct ScrubReadout<Content: View>: View {
    var onOpen: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        if let onOpen {
            Button {
                Haptics.light()
                onOpen()
            } label: {
                HStack(spacing: 8) {
                    content

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: AppLayout.minHitTarget)
                .contentShape(.rect)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Opens this take")
        } else {
            content
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Weekly Bucket

nonisolated struct WeeklyBucket: Identifiable, Equatable {
    let id: Date
    let avgFillers: Double
    let sessionCount: Int
}

// MARK: - Filler Trend Chart

struct FillerTrendChart: View {
    @State private var selectedIndex: Int?

    /// Weekly buckets, built once per `points` change like the other charts'
    /// `PlotModel`. As a computed property body regrouped every point about a
    /// dozen times per pass, and scrubbing runs a pass per step.
    private let weeklyData: [WeeklyBucket]
    private let overallTrend: Double

    init(points: [ChartRecordingPoint]) {
        _selectedIndex = State(initialValue: nil)

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { p in
            calendar.startOfDay(for: p.date.startOfWeek)
        }

        let weeks = grouped.map { (weekStart, recs) in
            let totalFillers = recs.map(\.fillerCount).reduce(0, +)
            let avg = recs.isEmpty ? 0 : Double(totalFillers) / Double(recs.count)
            return WeeklyBucket(id: weekStart, avgFillers: avg, sessionCount: recs.count)
        }
        .sorted { $0.id < $1.id }

        weeklyData = weeks
        overallTrend = weeks.count >= 2 ? weeks.last!.avgFillers - weeks.first!.avgFillers : 0
    }

    private var selectedBucketID: Date? {
        guard let selectedIndex, selectedIndex < weeklyData.count else { return nil }
        return weeklyData[selectedIndex].id
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Filler words per session", icon: "exclamationmark.bubble.fill") {
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
                                    .monospacedDigit()
                                    .foregroundStyle(week.avgFillers > 10 ? AppColors.error : week.avgFillers > 5 ? AppColors.warning : AppColors.success)
                                Text("avg fillers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(week.sessionCount == 1 ? "1 session" : "\(week.sessionCount) sessions")
                                .font(.caption)
                                .monospacedDigit()
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
    private let onOpenTake: ((UUID) -> Void)?

    init(points: [ChartRecordingPoint], onOpenTake: ((UUID) -> Void)? = nil) {
        _userSettings = Query()
        _selectedIndex = State(initialValue: nil)
        model = PlotModel(points: points)
        self.onOpenTake = onOpenTake
    }

    private func openAction(for id: UUID) -> (() -> Void)? {
        guard let onOpenTake else { return nil }
        return { onOpenTake(id) }
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
                                    .font(.caption2)
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
                        ScrubReadout(onOpen: openAction(for: point.id)) {
                            HStack(spacing: 12) {
                                Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 4) {
                                    Text("\(Int(point.wpm))")
                                        .font(.subheadline.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(inRange ? AppColors.success : AppColors.warning)
                                    Text("WPM")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 4)

                                Text(inRange ? "In range" : (point.wpm > targetWPM ? "Too fast" : "Too slow"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(inRange ? AppColors.success : AppColors.warning)
                            }
                        }
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
                    // Reached only when takes in the window carry no measured pace.
                    EmptyStateInline(
                        icon: "speedometer",
                        message: "Pace needs two takes with measured speech in this window."
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
                GlassCardTitle("Skill breakdown", icon: "star.fill") {
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

nonisolated private struct WeeklyFrequencyBucket: Identifiable, Equatable {
    let id: Date
    let sessionCount: Int
}

struct SessionFrequencyChart: View {
    @Query private var userSettings: [UserSettings]
    @State private var selectedIndex: Int?

    /// Built once per `points` change; see `FillerTrendChart.weeklyData`.
    /// Every week from the first practiced one to this one, empty weeks
    /// included: a week without a session is a miss, not a gap. Counting only
    /// practiced weeks let two good weeks out of ten read as a 100% hit rate.
    private let weeklyCounts: [WeeklyFrequencyBucket]
    private let currentWeek: Date

    init(points: [ChartRecordingPoint]) {
        _userSettings = Query()
        _selectedIndex = State(initialValue: nil)

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: points) { p in
            calendar.startOfDay(for: p.date.startOfWeek)
        }
        let thisWeek = calendar.startOfDay(for: Date.now.startOfWeek)
        currentWeek = thisWeek

        var buckets: [WeeklyFrequencyBucket] = []
        if let firstWeek = grouped.keys.min() {
            var week = firstWeek
            while week <= thisWeek {
                buckets.append(WeeklyFrequencyBucket(id: week, sessionCount: grouped[week]?.count ?? 0))
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
                week = calendar.startOfDay(for: next)
            }
        }
        weeklyCounts = buckets
    }

    private var weeklyGoal: Int {
        userSettings.first?.weeklyGoalSessions ?? 5
    }

    // Depends on the goal setting, so it stays computed; it walks the
    // already-built buckets, not the points. This week is still open: it
    // counts once it meets the goal, never as a miss before it is over.
    private var goalHitRate: Int {
        let judged = weeklyCounts.filter { $0.id < currentWeek || $0.sessionCount >= weeklyGoal }
        guard !judged.isEmpty else { return 0 }
        let hit = judged.filter { $0.sessionCount >= weeklyGoal }.count
        return Int(Double(hit) / Double(judged.count) * 100)
    }

    private var selectedWeekID: Date? {
        guard let selectedIndex, selectedIndex < weeklyCounts.count else { return nil }
        return weeklyCounts[selectedIndex].id
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                GlassCardTitle("Sessions per week", icon: "calendar") {
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
                                    .font(.caption2)
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
                                    .monospacedDigit()
                                    .foregroundStyle(week.sessionCount >= weeklyGoal ? AppColors.primary : .primary)
                                Text("/ \(weeklyGoal)")
                                    .font(.caption)
                                    .monospacedDigit()
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

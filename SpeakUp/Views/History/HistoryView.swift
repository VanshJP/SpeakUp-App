import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()
    @State private var selectedDate: Date?
    @State private var showingDayDetail = false
    @State private var selectedFilter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var summaryToDelete: RecordingSummary?
    @State private var showingDeleteAlert = false
    @State private var selectedSection: HistorySection = .recordings
    @Namespace private var pickerNamespace
    @Query private var userSettings: [UserSettings]

    var onSelectRecording: (String) -> Void
    var onShowBeforeAfter: () -> Void = {}
    var onShowJournalExport: () -> Void = {}
    var onShowGoals: () -> Void = {}

    // MARK: - Filtered Summaries

    private var filteredSummaries: [RecordingSummary] {
        var items = viewModel.summaries

        switch selectedFilter {
        case .all: break
        case .favorites:
            items = items.filter(\.isFavorite)
        case .highScore:
            items = items.filter { ($0.overallScore ?? 0) >= 80 }
        case .recent:
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
            items = items.filter { $0.date >= weekAgo }
        case .stories:
            items = items.filter { $0.storyId != nil }
        }

        if !searchText.isEmpty {
            items = items.filter { $0.searchableText.localizedStandardContains(searchText) }
        }

        return items
    }

    private var analyzedSummaries: [RecordingSummary] {
        viewModel.summaries.filter { $0.overallScore != nil }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppBackground()

            ZStack {
                switch selectedSection {
                case .recordings:
                    recordingsScrollView
                        .transition(.opacity)
                case .progress:
                    progressScrollView
                        .transition(.opacity)
                }
            }
        }
        .navigationTitle("History")
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search recordings...")
        .refreshable {
            await viewModel.loadData()
        }
        .onAppear {
            viewModel.configure(with: modelContext)
        }
        .sheet(isPresented: $showingDayDetail) {
            if let date = selectedDate {
                DayDetailSheet(
                    date: date,
                    summaries: viewModel.summariesForDate(date),
                    onSelectSummary: { summary in
                        showingDayDetail = false
                        onSelectRecording(summary.id.uuidString)
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .alert("Delete Recording?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let summary = summaryToDelete {
                    Task {
                        await viewModel.deleteRecording(id: summary.id)
                    }
                }
                summaryToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                summaryToDelete = nil
            }
        } message: {
            Text("This recording and its audio will be permanently deleted.")
        }
    }

    // MARK: - Recordings Scroll View

    private var recordingsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    quickStatsStrip
                    filterSection
                    recordingsSection
                } header: {
                    pinnedSectionPicker
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Progress Scroll View

    private var progressScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    contributionGraphSection
                    streakSection

                    if analyzedSummaries.count >= 2 {
                        progressChartsCard
                    }

                    if viewModel.summaries.count >= 2 {
                        progressReplayBanner
                    }

                    if analyzedSummaries.count >= 2 {
                        compareProgressCard
                    }

                    goalsSection
                    journalExportCard

                    vocabUsageSection
                } header: {
                    pinnedSectionPicker
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Pinned Section Picker

    private var pinnedSectionPicker: some View {
        sectionPicker
            .padding(.top, 4)
            .padding(.bottom, 10)
    }

    // MARK: - Quick Stats Strip

    private var quickStatsStrip: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 0) {
                quickStatItem(
                    icon: "flame.fill",
                    value: "\(viewModel.currentStreak)",
                    label: "Streak",
                    color: .orange,
                    isHighlighted: viewModel.currentStreak > 0
                )

                quickStatDivider

                quickStatItem(
                    icon: "mic.fill",
                    value: "\(viewModel.summaries.count)",
                    label: "Sessions",
                    color: .teal,
                    isHighlighted: false
                )

                quickStatDivider

                quickStatItem(
                    icon: "chart.line.uptrend.xyaxis",
                    value: averageScoreText,
                    label: "Avg Score",
                    color: averageScoreColor,
                    isHighlighted: false
                )
            }
        }
    }

    private var quickStatDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 32)
    }

    private func quickStatItem(
        icon: String,
        value: String,
        label: String,
        color: Color,
        isHighlighted: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isHighlighted ? color : color.opacity(0.75))

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(HistorySection.allCases) { section in
                sectionPickerItem(section)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    @ViewBuilder
    private func sectionPickerItem(_ section: HistorySection) -> some View {
        let isSelected = selectedSection == section
        Button {
            guard selectedSection != section else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(section.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.primary.opacity(0.85),
                                    AppColors.primary.opacity(0.55)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                        .shadow(color: AppColors.primary.opacity(0.45), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "historyPickerSelection", in: pickerNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contribution Graph Section

    private var contributionGraphSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity", systemImage: "chart.dots.scatter")
                    .font(.headline)

                Spacer()

                Text("Last 6 months")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GlassCard(padding: 0) {
                ContributionGraph(viewModel: viewModel) { date in
                    selectedDate = date
                    showingDayDetail = true
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 0) {
                StreakStatItem(
                    icon: "flame.fill",
                    value: "\(viewModel.currentStreak)",
                    label: "Current",
                    color: .orange,
                    isHighlighted: viewModel.currentStreak > 0
                )

                streakDivider

                StreakStatItem(
                    icon: "trophy.fill",
                    value: "\(viewModel.longestStreak)",
                    label: "Best",
                    color: .yellow,
                    isHighlighted: false
                )

                streakDivider

                StreakStatItem(
                    icon: "mic.fill",
                    value: "\(viewModel.summaries.count)",
                    label: "Sessions",
                    color: .teal,
                    isHighlighted: false
                )

                streakDivider

                StreakStatItem(
                    icon: "clock.fill",
                    value: totalPracticeTime,
                    label: "Time",
                    color: .purple,
                    isHighlighted: false
                )

                streakDivider

                StreakStatItem(
                    icon: "chart.line.uptrend.xyaxis",
                    value: averageScoreText,
                    label: "Avg",
                    color: averageScoreColor,
                    isHighlighted: false
                )
            }
        }
    }

    private var streakDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 40)
    }

    private var averageScoreText: String {
        guard let score = viewModel.averageScore else { return "—" }
        return "\(score)"
    }

    private var averageScoreColor: Color {
        guard let score = viewModel.averageScore else { return .gray }
        return AppColors.scoreColor(for: score)
    }

    private var totalPracticeTime: String {
        let totalSeconds = viewModel.totalPracticeTimeSeconds
        let minutes = Int(totalSeconds) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h\(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Vocab Usage Section

    @ViewBuilder
    private var vocabUsageSection: some View {
        let hasVocabWords = !(userSettings.first?.vocabWords ?? []).isEmpty
        let aggregated = viewModel.aggregatedVocab

        if hasVocabWords && !aggregated.isEmpty {
            let totalUses = aggregated.reduce(0) { $0 + $1.count }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Vocab Words", systemImage: "character.book.closed")
                        .font(.headline)

                    Spacer()

                    Text("\(totalUses) uses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(aggregated.prefix(15), id: \.word) { item in
                            HStack(spacing: 5) {
                                Text(item.word)
                                    .font(.caption.weight(.medium))
                                Text("\(item.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Circle().fill(.green))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.green.opacity(0.12)))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Progress Replay Banner

    private var progressReplayBanner: some View {
        Button {
            onShowBeforeAfter()
        } label: {
            FeaturedGlassCard(gradientColors: [.purple.opacity(0.15), .teal.opacity(0.08)]) {
                HStack(spacing: 14) {
                    Image(systemName: "headphones")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle().fill(.purple.opacity(0.15))
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Listen to Your Progress")
                            .font(.subheadline.weight(.semibold))

                        Text("Compare your first and latest recordings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress Charts Card

    private var progressChartsCard: some View {
        let recentScores: [(date: Date, score: Int)] = analyzedSummaries
            .sorted { $0.date < $1.date }
            .suffix(12)
            .compactMap { r in
                guard let score = r.overallScore else { return nil }
                return (date: r.date, score: score)
            }

        return NavigationLink {
            ProgressChartsView()
        } label: {
            FeaturedGlassCard(gradientColors: [.teal.opacity(0.1), .cyan.opacity(0.05)]) {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundStyle(.teal)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Progress Charts")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("View score trends, pace, fillers & more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Inline sparkline preview
                    if recentScores.count >= 3 {
                        Chart {
                            ForEach(Array(recentScores.enumerated()), id: \.offset) { _, point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(.teal.opacity(0.8))
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.catmullRom)

                                AreaMark(
                                    x: .value("Date", point.date),
                                    y: .value("Score", point.score)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.teal.opacity(0.2), .teal.opacity(0.01)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartYScale(domain: max(0, (recentScores.map(\.score).min() ?? 0) - 10)...min(100, (recentScores.map(\.score).max() ?? 100) + 10))
                        .frame(height: 48)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compare Progress Card

    private var compareProgressCard: some View {
        let sorted = analyzedSummaries.sorted { $0.date < $1.date }
        let firstScore = sorted.first?.overallScore ?? 0
        let latestScore = sorted.last?.overallScore ?? 0
        let change = latestScore - firstScore

        return NavigationLink {
            ComparisonView()
        } label: {
            FeaturedGlassCard(gradientColors: [.teal.opacity(0.15), .cyan.opacity(0.08)]) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Compare Progress", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 8) {
                            Text("\(firstScore)")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppColors.scoreColor(for: firstScore))

                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Text("\(latestScore)")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppColors.scoreColor(for: latestScore))
                        }

                        Text("First vs Latest Session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text(change >= 0 ? "+\(change)" : "\(change)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(change >= 0 ? .green : .red)

                        Text("change")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        Button {
            onShowGoals()
        } label: {
            GlassCard(tint: .purple.opacity(0.06)) {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.title3)
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goals")
                            .font(.subheadline.weight(.semibold))
                        Text("Set and track your speaking goals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Journal Export Card

    private var journalExportCard: some View {
        Button {
            onShowJournalExport()
        } label: {
            GlassCard(tint: .blue.opacity(0.06)) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Progress Journal")
                            .font(.subheadline.weight(.semibold))
                        Text("Generate a PDF summary of your journey")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { filter in
                    FilterChip(
                        title: filter.title,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        count: countForFilter(filter)
                    ) {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func countForFilter(_ filter: HistoryFilter) -> Int? {
        switch filter {
        case .all: return nil
        case .favorites: return viewModel.filterCounts[.favorites] ?? 0
        case .highScore: return viewModel.filterCounts[.highScore] ?? 0
        case .recent: return nil
        case .stories: return viewModel.filterCounts[.stories] ?? 0
        }
    }

    // MARK: - Recordings Section

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Sessions", systemImage: "list.bullet")
                    .font(.headline)

                Spacer()

                if !filteredSummaries.isEmpty {
                    Text("\(filteredSummaries.count) \(selectedFilter == .all ? "total" : "found")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if filteredSummaries.isEmpty {
                EmptyStateCard(
                    icon: selectedFilter == .all ? "mic.slash" : "magnifyingglass",
                    title: selectedFilter == .all ? "No Recordings Yet" : "No Matches",
                    message: selectedFilter == .all
                        ? "Complete your first practice session to see it here."
                        : "Try adjusting your filters or search terms."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredSummaries) { summary in
                        Button {
                            onSelectRecording(summary.id.uuidString)
                        } label: {
                            RecordingRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task {
                                    await viewModel.toggleFavorite(id: summary.id)
                                }
                            } label: {
                                Label(
                                    summary.isFavorite ? "Remove Favorite" : "Add to Favorites",
                                    systemImage: summary.isFavorite ? "heart.slash" : "heart"
                                )
                            }

                            Button(role: .destructive) {
                                summaryToDelete = summary
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - History Filter

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, favorites, highScore, recent, stories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .highScore: return "High Score"
        case .recent: return "This Week"
        case .stories: return "Stories"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
        case .highScore: return "star.fill"
        case .recent: return "clock"
        case .stories: return "book.pages"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var count: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)

                Text(title)
                    .font(.caption.weight(.medium))

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.teal.opacity(0.9), .teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        }
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak Stat Item

struct StreakStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Contribution Graph

struct ContributionGraph: View {
    let viewModel: HistoryViewModel
    var onDateSelected: ((Date) -> Void)?

    private let columns = 26
    private let rows = 7
    private let cellSpacing: CGFloat = 3
    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let legendIntensities: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(100, geometry.size.width - 28)
            let cellSize = max(8, (availableWidth - CGFloat(columns - 1) * cellSpacing) / CGFloat(columns))
            let cellHeight = cellSize * 1.4

            if cellSize > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: cellSpacing) {
                        VStack(alignment: .trailing, spacing: cellSpacing) {
                            ForEach(0..<rows, id: \.self) { index in
                                Text(index % 2 == 1 ? weekdayLabels[index] : "")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .frame(height: cellHeight)
                            }
                        }
                        .frame(width: 24)

                        HStack(spacing: cellSpacing) {
                            ForEach(0..<columns, id: \.self) { week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(0..<rows, id: \.self) { day in
                                        let date = dateForCell(week: week, day: day)
                                        let intensity = viewModel.activityLevel(for: date)

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(contributionColor(intensity: intensity))
                                            .frame(width: cellSize, height: cellHeight)
                                            .onTapGesture {
                                                if intensity > 0 {
                                                    onDateSelected?(date)
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Text("Less")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ForEach(0..<legendIntensities.count, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(contributionColor(intensity: legendIntensities[index]))
                                .frame(width: cellSize, height: cellSize)
                        }

                        Text("More")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(height: 160)
    }

    private func contributionColor(intensity: Double) -> Color {
        if intensity == 0 {
            return Color.gray.opacity(0.15)
        }
        return Color.teal.opacity(0.25 + (intensity * 0.75))
    }

    private func dateForCell(week: Int, day: Int) -> Date {
        let today = Date()
        let startOfWeek = today.startOfWeek
        let weeksBack = columns - 1 - week
        let targetWeek = startOfWeek.adding(weeks: -weeksBack)
        return targetWeek.adding(days: day)
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let summary: RecordingSummary

    private static let detailedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private var detailedDateString: String {
        Self.detailedDateFormatter.string(from: summary.date)
    }

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                // Mini score ring
                if let score = summary.overallScore {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 3)
                            .frame(width: 40, height: 40)
                        Circle()
                            .trim(from: 0, to: CGFloat(score) / 100)
                            .stroke(
                                AppColors.scoreColor(for: score),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))
                        Text("\(score)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.scoreColor(for: score))
                    }
                } else if summary.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 40, height: 40)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            (PromptCategory(rawValue: summary.promptCategory ?? "")?.color ?? .teal)
                        )
                        .frame(width: 4, height: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(summary.displayTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        if summary.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    HStack(spacing: 6) {
                        if let category = summary.promptCategory {
                            Text(category)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(PromptCategory(rawValue: category)?.color ?? .teal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule()
                                        .fill((PromptCategory(rawValue: category)?.color ?? .teal).opacity(0.15))
                                }
                        }

                        if summary.storyId != nil {
                            HStack(spacing: 3) {
                                Image(systemName: "book.pages")
                                    .font(.system(size: 8))
                                Text("Story")
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(.purple.opacity(0.15))
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Text(detailedDateString)
                        Text("·")
                        Text(summary.formattedDuration)

                        if let wpm = summary.wpm {
                            Text("·")
                            HStack(spacing: 2) {
                                Image(systemName: "metronome")
                                    .font(.system(size: 8))
                                Text("\(Int(wpm)) wpm")
                            }
                            .foregroundStyle(.teal)
                        }

                        if let fillers = summary.fillerCount, fillers > 0 {
                            Text("·")
                            HStack(spacing: 2) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 8))
                                Text("\(fillers)")
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Day Detail Sheet

struct DayDetailSheet: View {
    let date: Date
    let summaries: [RecordingSummary]
    let onSelectSummary: (RecordingSummary) -> Void

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    private var formattedDate: String {
        Self.fullDateFormatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if summaries.isEmpty {
                        ContentUnavailableView(
                            "No Recordings",
                            systemImage: "mic.slash",
                            description: Text("No practice sessions on this day.")
                        )
                    } else {
                        ForEach(summaries) { summary in
                            Button {
                                onSelectSummary(summary)
                            } label: {
                                RecordingRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - History Section Enum

enum HistorySection: String, CaseIterable, Identifiable {
    case recordings
    case progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recordings: return "Recordings"
        case .progress: return "Progress"
        }
    }

    var icon: String {
        switch self {
        case .recordings: return "waveform"
        case .progress: return "chart.line.uptrend.xyaxis"
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(onSelectRecording: { _ in }, onShowBeforeAfter: {}, onShowJournalExport: {})
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}

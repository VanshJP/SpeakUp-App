import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()
    @State private var selectedDate: Date?
    @State private var showingDayDetail = false
    @State private var selectedFilter: HistoryFilter = .all
    @State private var searchText = ""
    @Query private var userSettings: [UserSettings]

    var onSelectRecording: (String) -> Void
    var onShowBeforeAfter: () -> Void = {}
    var onShowJournalExport: () -> Void = {}

    private var filteredRecordings: [Recording] {
        var recordings = viewModel.recordings

        // Apply filter
        switch selectedFilter {
        case .all: break
        case .favorites:
            recordings = recordings.filter(\.isFavorite)
        case .highScore:
            recordings = recordings.filter { ($0.analysis?.speechScore.overall ?? 0) >= 80 }
        case .recent:
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
            recordings = recordings.filter { $0.date >= weekAgo }
        }

        // Apply search
        if !searchText.isEmpty {
            recordings = recordings.filter { recording in
                let promptText = recording.prompt?.text ?? ""
                let category = recording.prompt?.category ?? ""
                let transcript = recording.transcriptionText ?? ""
                let query = searchText.lowercased()
                return promptText.lowercased().contains(query)
                    || category.lowercased().contains(query)
                    || transcript.lowercased().contains(query)
            }
        }

        return recordings
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    // Contribution Graph
                    contributionGraphSection

                    // Streak Stats
                    streakSection

                    // Vocab Word Usage
                    vocabUsageSection

                    // Listen to Your Progress
                    if viewModel.recordings.count >= 5 {
                        progressReplayBanner
                    }

                    // Compare Progress
                    if analyzedRecordings.count >= 2 {
                        compareProgressCard
                    }

                    // Filter & Search
                    filterSection

                    // Recent Recordings
                    recordingsSection
                }
                .padding()
            }
        }
        .navigationTitle("History")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onShowJournalExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
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
                    recordings: viewModel.recordingsForDate(date),
                    onSelectRecording: { recording in
                        showingDayDetail = false
                        onSelectRecording(recording.id.uuidString)
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
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

            GlassCard {
                ContributionGraph(viewModel: viewModel) { date in
                    selectedDate = date
                    showingDayDetail = true
                }
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

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 0.5, height: 40)

                StreakStatItem(
                    icon: "trophy.fill",
                    value: "\(viewModel.longestStreak)",
                    label: "Best",
                    color: .yellow,
                    isHighlighted: false
                )

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 0.5, height: 40)

                StreakStatItem(
                    icon: "mic.fill",
                    value: "\(viewModel.recordings.count)",
                    label: "Sessions",
                    color: .teal,
                    isHighlighted: false
                )

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 0.5, height: 40)

                StreakStatItem(
                    icon: "clock.fill",
                    value: totalPracticeTime,
                    label: "Time",
                    color: .purple,
                    isHighlighted: false
                )

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 0.5, height: 40)

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

    private var averageScoreText: String {
        let scores = viewModel.recordings.compactMap { $0.analysis?.speechScore.overall }
        guard !scores.isEmpty else { return "—" }
        return "\(scores.reduce(0, +) / scores.count)"
    }

    private var averageScoreColor: Color {
        let scores = viewModel.recordings.compactMap { $0.analysis?.speechScore.overall }
        guard !scores.isEmpty else { return .gray }
        return AppColors.scoreColor(for: scores.reduce(0, +) / scores.count)
    }

    private var totalPracticeTime: String {
        let totalSeconds = viewModel.recordings.reduce(0.0) { $0 + $1.actualDuration }
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
        let aggregated = aggregateVocabUsage()

        if hasVocabWords && !aggregated.isEmpty {
            let totalUses = aggregated.reduce(0) { $0 + $1.value }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Vocab Words", systemImage: "character.book.closed")
                        .font(.headline)

                    Spacer()

                    Text("\(totalUses) uses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(aggregated.prefix(15), id: \.key) { item in
                            HStack(spacing: 5) {
                                Text(item.key)
                                    .font(.caption.weight(.medium))
                                Text("\(item.value)")
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
            }
        }
    }

    private func aggregateVocabUsage() -> [(key: String, value: Int)] {
        var aggregated: [String: Int] = [:]
        for recording in viewModel.recordings {
            guard let usage = recording.analysis?.vocabWordsUsed else { continue }
            for item in usage {
                aggregated[item.word, default: 0] += item.count
            }
        }
        return aggregated.sorted { $0.value > $1.value }
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

    // MARK: - Analyzed Recordings Helper

    private var analyzedRecordings: [Recording] {
        viewModel.recordings.filter { $0.analysis != nil }
    }

    // MARK: - Compare Progress Card

    private var compareProgressCard: some View {
        let sorted = analyzedRecordings.sorted { $0.date < $1.date }
        let firstScore = sorted.first?.analysis?.speechScore.overall ?? 0
        let latestScore = sorted.last?.analysis?.speechScore.overall ?? 0
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

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
    }

    private func countForFilter(_ filter: HistoryFilter) -> Int? {
        switch filter {
        case .all: return nil
        case .favorites: return viewModel.recordings.filter(\.isFavorite).count
        case .highScore: return viewModel.recordings.filter { ($0.analysis?.speechScore.overall ?? 0) >= 80 }.count
        case .recent: return nil
        }
    }

    // MARK: - Recordings Section

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Sessions", systemImage: "list.bullet")
                    .font(.headline)

                Spacer()

                if !filteredRecordings.isEmpty {
                    Text("\(filteredRecordings.count) \(selectedFilter == .all ? "total" : "found")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if filteredRecordings.isEmpty {
                EmptyStateCard(
                    icon: selectedFilter == .all ? "mic.slash" : "magnifyingglass",
                    title: selectedFilter == .all ? "No Recordings Yet" : "No Matches",
                    message: selectedFilter == .all
                        ? "Complete your first practice session to see it here."
                        : "Try adjusting your filters or search terms."
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredRecordings) { recording in
                        RecordingRow(recording: recording)
                            .onTapGesture {
                                onSelectRecording(recording.id.uuidString)
                            }
                            .contextMenu {
                                Button {
                                    Task {
                                        await viewModel.toggleFavorite(recording)
                                    }
                                } label: {
                                    Label(
                                        recording.isFavorite ? "Remove Favorite" : "Add to Favorites",
                                        systemImage: recording.isFavorite ? "heart.slash" : "heart"
                                    )
                                }

                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteRecording(recording)
                                    }
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

// MARK: - History Filter Enum

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case highScore
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .highScore: return "High Score"
        case .recent: return "This Week"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
        case .highScore: return "star.fill"
        case .recent: return "clock"
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

private struct StreakStatItem: View {
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

    private let columns = 26 // 26 weeks (half year)
    private let rows = 7 // Days of week
    private let cellSpacing: CGFloat = 3

    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let legendIntensities: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(100, geometry.size.width - 28)
            let cellSize = max(8, (availableWidth - CGFloat(columns - 1) * cellSpacing) / CGFloat(columns))

            if cellSize > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    // Weekday labels
                    HStack(spacing: cellSpacing) {
                        VStack(alignment: .trailing, spacing: cellSpacing) {
                            ForEach(0..<rows, id: \.self) { index in
                                Text(index % 2 == 1 ? weekdayLabels[index] : "")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .frame(height: cellSize)
                            }
                        }
                        .frame(width: 24)

                        // Grid
                        HStack(spacing: cellSpacing) {
                            ForEach(0..<columns, id: \.self) { week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(0..<rows, id: \.self) { day in
                                        let date = dateForCell(week: week, day: day)
                                        let intensity = viewModel.activityLevel(for: date)

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(contributionColor(intensity: intensity))
                                            .frame(width: cellSize, height: cellSize)
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

                    // Legend
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
        .frame(height: 120)
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
    let recording: Recording

    private var detailedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: recording.date)
    }

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                // Media Type Icon with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.teal.opacity(0.15), .cyan.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: recording.mediaType.iconName)
                        .foregroundStyle(.teal)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(recording.displayTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        if recording.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Category badge
                    if let category = recording.prompt?.category {
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

                    HStack(spacing: 6) {
                        Text(detailedDateString)
                        Text("·")
                        Text(recording.formattedDuration)

                        if let wpm = recording.analysis?.wordsPerMinute {
                            Text("·")
                            HStack(spacing: 2) {
                                Image(systemName: "metronome")
                                    .font(.system(size: 8))
                                Text("\(Int(wpm)) wpm")
                            }
                            .foregroundStyle(.teal)
                        }

                        if let fillers = recording.analysis?.totalFillerCount, fillers > 0 {
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

                // Score
                if let score = recording.analysis?.speechScore.overall {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(score)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColors.scoreColor(for: score))

                        Text("score")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if recording.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Day Detail Sheet

struct DayDetailSheet: View {
    let date: Date
    let recordings: [Recording]
    let onSelectRecording: (Recording) -> Void

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if recordings.isEmpty {
                        ContentUnavailableView(
                            "No Recordings",
                            systemImage: "mic.slash",
                            description: Text("No practice sessions on this day.")
                        )
                    } else {
                        ForEach(recordings) { recording in
                            RecordingRow(recording: recording)
                                .onTapGesture {
                                    onSelectRecording(recording)
                                }
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

#Preview {
    NavigationStack {
        HistoryView(onSelectRecording: { _ in }, onShowBeforeAfter: {}, onShowJournalExport: {})
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserGoal.self, UserSettings.self], inMemory: true)
}

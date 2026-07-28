import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()
    @State private var selectedFilter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var summaryToDelete: RecordingSummary?
    @State private var showingDeleteAlert = false
    @State private var selectedSection: HistorySection = .recordings
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
        case .stories:
            items = items.filter { $0.storyId != nil }
        }

        if !searchText.isEmpty {
            items = items.filter { $0.searchableText.localizedStandardContains(searchText) }
        }

        return items
    }


    // MARK: - Body

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        switch selectedSection {
                        case .recordings:
                            // The strip earns its place back by being
                            // switchable — showing up and doing well are
                            // different questions, and one grid answers both.
                            // Suppressed while searching or filtering, where
                            // the list is the answer and the grid is noise.
                            if searchText.isEmpty, selectedFilter == .all, !viewModel.summaries.isEmpty {
                                ActivityStrip(summaries: viewModel.summaries)
                            }

                            recordingsSection
                                .transition(.opacity)
                        case .progress:
                            progressContent
                                .transition(.opacity)
                        }
                    } header: {
                        pinnedSectionPicker
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("History")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if selectedSection == .recordings {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
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

    // MARK: - Progress Content

    // The Progress tab now shows the charts directly — the same experience the
    // old "Progress Charts" card used to navigate to. Secondary tools
    // (compare, replay, goals, journal) are folded into one compact card.
    @ViewBuilder
    private var progressContent: some View {
        ProgressChartsContent()
        progressToolsSection
        vocabUsageSection
    }

    // MARK: - Progress Tools (compact secondary actions)

    private var progressToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("More", icon: "ellipsis.circle")

            GlassCard(padding: 16) {
                VStack(spacing: 0) {
                    if viewModel.summaries.count >= 2 {
                        NavigationLink { ComparisonView() } label: {
                            toolRowLabel(icon: "arrow.left.arrow.right", title: "Compare Sessions")
                        }
                        .buttonStyle(GlassPressStyle())
                        toolDivider
                        Button { onShowBeforeAfter() } label: {
                            toolRowLabel(icon: "headphones", title: "Listen to Progress")
                        }
                        .buttonStyle(GlassPressStyle())
                        toolDivider
                    }

                    Button { onShowGoals() } label: {
                        toolRowLabel(icon: "target", title: "Goals")
                    }
                    .buttonStyle(GlassPressStyle())
                    toolDivider
                    Button { onShowJournalExport() } label: {
                        toolRowLabel(icon: "square.and.arrow.up", title: "Export Journal")
                    }
                    .buttonStyle(GlassPressStyle())
                }
            }
        }
    }

    private var toolDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
    }

    private func toolRowLabel(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppColors.primary)
                .frame(width: 26)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Pinned Section Picker

    private var pinnedSectionPicker: some View {
        sectionPicker
            .padding(.top, 4)
            .padding(.bottom, 10)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        SectionPicker(
            sections: HistorySection.allCases,
            selection: $selectedSection,
            label: { $0.label },
            icon: { $0.icon }
        )
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
                                    .background(Circle().fill(AppColors.success))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AppColors.success.opacity(0.12)))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Filter Menu

    /// Filters live in the toolbar, not in a chip row above the list — three
    /// options don't justify a scrolling row between you and your sessions.
    private var filterMenu: some View {
        Menu {
            ForEach(HistoryFilter.allCases) { filter in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(duration: 0.3)) {
                        selectedFilter = filter
                    }
                } label: {
                    HStack {
                        Label(filter.title, systemImage: filter.icon)
                        if selectedFilter == filter { Spacer(); Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.body.weight(.semibold))
                .symbolVariant(selectedFilter == .all ? .none : .fill)
        }
        .accessibilityLabel("Filter sessions")
    }

    // MARK: - Recordings Section

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Only speak up when a filter is narrowing the list — the tab is
            // already called History, so "Sessions · 42 total" said nothing.
            if selectedFilter != .all && !filteredSummaries.isEmpty {
                HStack(spacing: 6) {
                    Text("\(filteredSummaries.count) \(selectedFilter.title.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Haptics.light()
                        withAnimation(.spring(duration: 0.3)) { selectedFilter = .all }
                    } label: {
                        Text("Clear")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
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

/// Three filters, not five. "High Score" and "This Week" were slicing a list
/// that is already reverse-chronological and searchable — scrolling answered
/// both faster than a chip did.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, favorites, stories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .stories: return "Stories"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
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
                        .foregroundStyle(isSelected ? Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.6) : Color.secondary)
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Color(red: 0.07, green: 0.07, blue: 0.08)) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.92))
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

    /// One plain-language metadata line: date · duration · category. Color
    /// and chips stay out of the list — the score gauge on the right is the
    /// only colored element, so rows scan instead of shouting.
    private var metadataLine: String {
        var parts = [detailedDateString, summary.formattedDuration]
        if summary.storyId != nil {
            parts.append("Story")
        } else if let category = summary.promptCategory {
            parts.append(category)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(summary.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if summary.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColors.error)
                        }
                    }

                    Text(metadataLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let wpm = summary.wpm {
                        HStack(spacing: 8) {
                            Text("\(Int(wpm)) wpm")
                            if let fillers = summary.fillerCount, fillers > 0 {
                                Text("\(fillers) filler\(fillers == 1 ? "" : "s")")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                // Score gauge — the row's single colored element
                if let score = summary.overallScore {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 3.5)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: CGFloat(score) / 100)
                            .stroke(
                                AppColors.scoreColor(for: score),
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                        Text("\(score)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                } else if summary.isProcessing {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 3.5)
                            .frame(width: 44, height: 44)
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                } else {
                    Image(systemName: "waveform")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
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

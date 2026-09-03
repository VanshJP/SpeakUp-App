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

            PageScrollView {
                LazyVStack(spacing: AppLayout.listSpacing, pinnedViews: [.sectionHeaders]) {
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
                .pageContentInsets()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
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

    // The Progress tab shows the charts directly — the same experience the
    // old "Progress Charts" card used to navigate to. One VStack owns the
    // page rhythm: every chapter (conclusion, trends, guidance, review) sits
    // 20pt apart. Word Bank usage renders inside the Language tab now, so the
    // page ends at Review instead of an orphaned chip rail.
    //
    // Review tiles (compare / listen back / goals / journal) stay here — they
    // need history data. Library → Tools is prep (warm-up, drill, read aloud,
    // calm); mixing the two catalogs muddies both.
    private var progressContent: some View {
        VStack(spacing: AppLayout.chapterSpacing) {
            ProgressChartsContent(vocabWords: viewModel.aggregatedVocab)
            progressToolsSection
        }
    }

    // MARK: - Progress Tools (compact secondary actions)

    private var progressToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Review", icon: "ellipsis.circle")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                if viewModel.summaries.count >= 2 {
                    NavigationLink { ComparisonView() } label: {
                        ToolTileLabel(icon: "arrow.left.arrow.right", title: "Compare", tint: AppColors.categoryIndigo)
                    }
                    .buttonStyle(GlassPressStyle())

                    Button { onShowBeforeAfter() } label: {
                        ToolTileLabel(icon: "headphones", title: "Listen back", tint: AppColors.categoryPlum)
                    }
                    .buttonStyle(GlassPressStyle())
                }

                Button { onShowGoals() } label: {
                    ToolTileLabel(icon: "target", title: "Goals", tint: AppColors.categorySage)
                }
                .buttonStyle(GlassPressStyle())

                Button { onShowJournalExport() } label: {
                    ToolTileLabel(icon: "square.and.arrow.up", title: "Journal", tint: AppColors.categoryAmber)
                }
                .buttonStyle(GlassPressStyle())
            }
        }
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
                    title: selectedFilter == .all ? "No recordings yet" : "No matches",
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
    /// Identity color for chips that stand for a user-owned thing (a Story
    /// folder). Idle chips wear it on the glyph; selected chips are the solid
    /// white pill either way, so selection always reads the same.
    var tint: Color? = nil
    let action: () -> Void

    /// Ink on a selected (solid white) chip.
    private static let onLight = Color(red: 0.07, green: 0.07, blue: 0.08)

    private var iconStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Self.onLight) }
        return tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(iconStyle)

                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected ? Self.onLight.opacity(0.6) : Color.secondary)
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Self.onLight) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: AppLayout.minHitTarget)
            .contentShape(Capsule())
            .modifier(SelectedFilterChrome(isSelected: isSelected))
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                        RingProgress(
                            progress: Double(score) / 100,
                            color: AppColors.scoreColor(for: score),
                            lineWidth: 3.5
                        )
                        .frame(width: 44, height: 44)
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
                } else if summary.hasError {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(AppColors.warning)
                        .frame(width: 44, height: 44)
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

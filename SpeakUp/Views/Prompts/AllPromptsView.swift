import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Per-category prompt totals with answered counts — built once per load so
/// the category grid does two dictionary lookups per tile instead of two
/// full-array reduces. Keyed by raw category string.
nonisolated struct PromptCategoryProgress {
    let total: Int
    let answered: Int
}

struct AllPromptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Prompt.category) private var allPrompts: [Prompt]

    @State private var answeredPromptIDs: Set<String> = []
    @State private var categoryCounts: [String: PromptCategoryProgress] = [:]
    @State private var selectedFilter: PromptFilter = .all
    @State private var selectedCategory: PromptCategory?
    @State private var selectedDifficulty: PromptDifficulty?
    @State private var showingAddPrompt = false
    @State private var showingFileImporter = false
    @State private var importConfirmation: ImportConfirmation?
    @State private var csvService = PromptCSVService()
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var promptToDelete: Prompt?
    @State private var showingPromptWheel = false

    let onSelectPrompt: ((Prompt) -> Void)?
    private let searchText: String

    init(
        onSelectPrompt: ((Prompt) -> Void)? = nil,
        searchText: String = ""
    ) {
        self.onSelectPrompt = onSelectPrompt
        self.searchText = searchText
    }
}

extension AllPromptsView {

    // MARK: - Computed Data

    private var customCount: Int {
        allPrompts.filter(\.isUserCreated).count
    }

    private var filteredPrompts: [Prompt] {
        var prompts = allPrompts

        switch selectedFilter {
        case .all: break
        case .unanswered: prompts = prompts.filter { !answeredPromptIDs.contains($0.id) }
        case .myPrompts: prompts = prompts.filter { $0.isUserCreated }
        }

        if let category = selectedCategory {
            prompts = prompts.filter { $0.category == category.rawValue }
        }

        if let difficulty = selectedDifficulty {
            prompts = prompts.filter { $0.difficulty == difficulty }
        }

        if !searchText.isEmpty {
            prompts = prompts.filter { $0.text.localizedStandardContains(searchText) }
        }

        prompts.sort { $0.category < $1.category }
        return prompts
    }

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedDifficulty != nil
    }

    // MARK: - Body

    var body: some View {
        // One filter+sort pass per render, threaded down to every consumer.
        let prompts = filteredPrompts

        return screenDecorations(
            VStack(spacing: 16) {
                if selectedCategory == nil {
                    VStack(spacing: 16) {
                        filterChips
                        landingContent(prompts)
                    }
                    .transition(.asymmetric(
                        insertion: .push(from: .leading),
                        removal: .push(from: .trailing)
                    ))
                } else {
                    categoryDetailContent(prompts)
                        .transition(.asymmetric(
                            insertion: .push(from: .trailing),
                            removal: .push(from: .leading)
                        ))
                }
            },
            prompts: prompts
        )
    }

    /// Sheet/importer/alert tail, kept out of `body` so each builder
    /// expression stays inside the compiler's type-check budget.
    private func screenDecorations(_ base: some View, prompts: [Prompt]) -> some View {
        base
            .task {
                await loadAnsweredPromptIDs()
            }
            .onChange(of: allPrompts.count) { _, _ in
                Task { await loadAnsweredPromptIDs() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarFilterMenu(prompts)
                }
            }
            .sheet(isPresented: $showingAddPrompt) {
                AddPromptView()
            }
            .sheet(isPresented: $showingPromptWheel) {
                PromptWheelView { prompt in
                    showingPromptWheel = false
                    if let onSelectPrompt {
                        onSelectPrompt(prompt)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [UTType.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Import Prompts", isPresented: Binding(
                get: { importConfirmation != nil },
                set: { if !$0 { importConfirmation = nil } }
            )) {
                Button("Cancel", role: .cancel) { importConfirmation = nil }
                Button("Import") { confirmImport() }
            } message: {
                if let confirmation = importConfirmation {
                    let newCount = confirmation.newCount
                    let dupeCount = confirmation.duplicateCount
                    if dupeCount > 0 {
                        Text("Import \(newCount) new prompt\(newCount == 1 ? "" : "s")? (\(dupeCount) duplicate\(dupeCount == 1 ? "" : "s") will be skipped.)")
                    } else {
                        Text("Import \(newCount) prompt\(newCount == 1 ? "" : "s")? They will be added as custom prompts.")
                    }
                }
            }
            .alert("Delete Prompt?", isPresented: Binding(
                get: { promptToDelete != nil },
                set: { if !$0 { promptToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { promptToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let prompt = promptToDelete {
                        deletePrompt(prompt)
                    }
                    promptToDelete = nil
                }
            } message: {
                Text("This prompt will be permanently deleted.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
    }
    // MARK: - Toolbar Menus

    private func toolbarFilterMenu(_ prompts: [Prompt]) -> some View {
        Menu {
            Section("Export & Import") {
                Button {
                    csvService.shareCSV(prompts: prompts)
                } label: {
                    Label(
                        hasActiveFilters ? "Export Filtered (\(prompts.count))" : "Export All Prompts",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(prompts.isEmpty)

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
            }

            Section("Difficulty") {
                Button {
                    withAnimation { selectedDifficulty = nil }
                } label: {
                    HStack {
                        Label("Any Difficulty", systemImage: "speedometer")
                        if selectedDifficulty == nil { Spacer(); Image(systemName: "checkmark") }
                    }
                }

                ForEach(PromptDifficulty.allCases, id: \.self) { difficulty in
                    Button {
                        withAnimation { selectedDifficulty = difficulty }
                    } label: {
                        HStack {
                            Label(difficulty.displayName, systemImage: difficultyIcon(difficulty))
                            if selectedDifficulty == difficulty { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.body.weight(.semibold))
                .symbolVariant(hasActiveFilters ? .fill : .none)
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(PromptFilter.allCases) { filter in
                    FilterChip(
                        title: filter.displayName,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        count: countForFilter(filter)
                    ) {
                        Haptics.light()
                        withAnimation(.spring(duration: 0.3)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func countForFilter(_ filter: PromptFilter) -> Int? {
        switch filter {
        case .all: return nil
        case .unanswered: return allPrompts.count - answeredPromptIDs.count
        case .myPrompts: return customCount
        }
    }

    // MARK: - Active Filters Row

    @ViewBuilder
    private var activeFiltersRow: some View {
        if let difficulty = selectedDifficulty {
            HStack(spacing: 6) {
                activeFilterTag(
                    icon: difficultyIcon(difficulty),
                    label: difficulty.displayName,
                    color: difficulty.color
                ) {
                    withAnimation { selectedDifficulty = nil }
                }
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func activeFilterTag(icon: String, label: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            onRemove()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(color.opacity(0.12))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Landing Content (Category-First)

    @ViewBuilder
    private func landingContent(_ prompts: [Prompt]) -> some View {
        spinTheWheelCard

        // A non-"All" chip is a request to see prompts, not categories —
        // otherwise the chips do nothing on this screen.
        if selectedFilter == .all {
            categoriesSection
        } else {
            HStack { countLabel(prompts); Spacer(minLength: 0) }
            promptResults(prompts)
        }
    }

    private func countLabel(_ prompts: [Prompt]) -> some View {
        Text("\(prompts.count) prompt\(prompts.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Spin the Wheel Card

    private var spinTheWheelCard: some View {
        Button {
            Haptics.medium()
            showingPromptWheel = true
        } label: {
            FeaturedGlassCard(cornerRadius: 20, padding: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Spin the Wheel")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Discover a random prompt")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    // The one high-contrast element on this screen.
                    Text("Spin")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background { Capsule().fill(Color.white.opacity(0.92)) }
                }
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    // MARK: - Categories Grid

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Categories", icon: "square.grid.2x2.fill")

            let columns = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(PromptCategory.allCases, id: \.self) { category in
                    categoryGridCard(category)
                }
            }
        }
    }

    private func categoryGridCard(_ category: PromptCategory) -> some View {
        let progress = categoryCounts[category.rawValue]
        let total = progress?.total ?? 0
        let done = progress?.answered ?? 0
        let color = category.color

        return Button {
            Haptics.medium()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                selectedCategory = category
            }
        } label: {
            GlassCard(cornerRadius: 16, padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: category.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)

                        Spacer(minLength: 0)

                        Text("\(done)/\(total)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }

                    Text(category.shortName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Progress is the data — the only place color earns its keep.
                    // Tick count is high enough that ticks stay taller than
                    // they are wide, otherwise they read as a row of dots.
                    TickMeter(
                        fraction: total > 0 ? Double(done) / Double(total) : 0,
                        color: color,
                        tickCount: 22
                    )
                    .frame(height: 7)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    // MARK: - Category Detail Content

    @ViewBuilder
    private func categoryDetailContent(_ prompts: [Prompt]) -> some View {
        HStack(spacing: 10) {
            backToCategoriesButton
            countLabel(prompts)
            Spacer(minLength: 0)
        }
        activeFiltersRow
        promptResults(prompts)
    }

    @ViewBuilder
    private func promptResults(_ prompts: [Prompt]) -> some View {
        if prompts.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 12) {
                listSection(prompts: prompts)
            }
        }
    }

    private var backToCategoriesButton: some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                selectedCategory = nil
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                if let category = selectedCategory {
                    Image(systemName: category.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(category.color)
                    Text(category.shortName)
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background { Capsule().fill(.ultraThinMaterial) }
            .overlay { Capsule().stroke(AppColors.cardStroke, lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prompt List & Grid

    @ViewBuilder
    private func listSection(prompts: [Prompt]) -> some View {
        ForEach(prompts, id: \.id) { prompt in
            PromptRow(
                prompt: prompt,
                isAnswered: answeredPromptIDs.contains(prompt.id),
                onTap: onSelectPrompt.map { selectAction in
                    {
                        Haptics.medium()
                        selectAction(prompt)
                    }
                },
                onDelete: prompt.isUserCreated ? {
                    promptToDelete = prompt
                } : nil
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateCard(
            icon: selectedFilter == .myPrompts ? "text.badge.plus" : "magnifyingglass",
            title: selectedFilter == .myPrompts ? "No Custom Prompts Yet" : "No Prompts Found",
            message: selectedFilter == .myPrompts
                ? "Create your first custom prompt to get started."
                : "Try adjusting your search or filters.",
            buttonTitle: selectedFilter == .myPrompts ? "Add Prompt" : nil,
            buttonAction: selectedFilter == .myPrompts ? { showingAddPrompt = true } : nil
        )
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func loadAnsweredPromptIDs() async {
        let container = modelContext.container
        let result = await Task.detached(priority: .userInitiated) { () -> (ids: Set<String>, counts: [String: PromptCategoryProgress]) in
            let context = ModelContext(container)
            let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
            let prompts = (try? context.fetch(FetchDescriptor<Prompt>())) ?? []

            // Denormalized promptId keeps the common path off relationship
            // traversal. Rows written before the column existed carry nil, so
            // fall back to the relationship — and write the backfill through
            // this context so the fast path converges.
            let categoryByPromptID = Dictionary(
                prompts.map { ($0.id, $0.category) },
                uniquingKeysWith: { first, _ in first }
            )

            var ids: Set<String> = []
            ids.reserveCapacity(recordings.count)
            var answeredByCategory: [String: Int] = [:]
            for recording in recordings {
                guard let promptId = recording.promptId ?? recording.prompt?.id else { continue }
                if recording.promptId == nil {
                    recording.promptId = promptId
                }
                if ids.insert(promptId).inserted, let category = categoryByPromptID[promptId] {
                    answeredByCategory[category, default: 0] += 1
                }
            }
            if context.hasChanges {
                try? context.save()
            }

            var totals: [String: Int] = [:]
            for prompt in prompts {
                totals[prompt.category, default: 0] += 1
            }

            var counts: [String: PromptCategoryProgress] = [:]
            for (category, total) in totals {
                counts[category] = PromptCategoryProgress(
                    total: total,
                    answered: answeredByCategory[category] ?? 0
                )
            }
            return (ids, counts)
        }.value
        answeredPromptIDs = result.ids
        categoryCounts = result.counts
    }

    private func deletePrompt(_ prompt: Prompt) {
        withAnimation {
            modelContext.delete(prompt)
            try? modelContext.save()
            Haptics.success()
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try csvService.parseCSV(from: url)
                let existingTexts = Set(allPrompts.map { $0.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
                let (newItems, dupeCount) = deduplicateImport(data, existingTexts: existingTexts)
                importConfirmation = ImportConfirmation(data: newItems, duplicateCount: dupeCount)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func deduplicateImport(_ data: [PromptImportData], existingTexts: Set<String>) -> (items: [PromptImportData], duplicates: Int) {
        var seen = existingTexts
        var unique: [PromptImportData] = []
        var dupeCount = 0

        for item in data {
            let normalized = item.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.contains(normalized) {
                dupeCount += 1
            } else {
                seen.insert(normalized)
                unique.append(item)
            }
        }

        return (unique, dupeCount)
    }

    private func confirmImport() {
        guard let confirmation = importConfirmation else { return }
        for item in confirmation.data {
            let prompt = Prompt(
                id: "user-\(UUID().uuidString)",
                text: item.text,
                category: item.category,
                difficulty: item.difficulty,
                isUserCreated: true
            )
            modelContext.insert(prompt)
        }
        try? modelContext.save()
        Haptics.success()
        importConfirmation = nil
    }

    private func difficultyIcon(_ difficulty: PromptDifficulty) -> String {
        switch difficulty {
        case .easy: return "hare"
        case .medium: return "figure.walk"
        case .hard: return "flame"
        }
    }

}

// MARK: - Import Confirmation

private struct ImportConfirmation {
    let data: [PromptImportData]
    let duplicateCount: Int

    var newCount: Int { data.count }
}

// MARK: - Prompt Filter Enum

/// Three filters, not five. "Default" was just the inverse of "My Prompts",
/// and "Answered" is already visible as the x/y count on every category tile.
enum PromptFilter: String, CaseIterable, Identifiable {
    case all
    case unanswered
    case myPrompts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .unanswered: return "Unanswered"
        case .myPrompts: return "My Prompts"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .unanswered: return "circle.dashed"
        case .myPrompts: return "person.fill"
        }
    }
}

// MARK: - Prompt Row

struct PromptRow: View {
    let prompt: Prompt
    var isAnswered: Bool = false
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        let content = GlassCard(cornerRadius: 16, padding: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt.text)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    PromptMetaLine(prompt: prompt)
                }

                Spacer(minLength: 4)

                if isAnswered {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppColors.success)
                } else if onTap != nil {
                    Image(systemName: "mic.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            // Category identity as a full-height rail, not a badge — one
            // colored element instead of three competing chips.
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(categoryColor)
                    .frame(width: 2.5)
            }
        }

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .contextMenu { contextMenuItems }
        } else {
            content
                .contextMenu { contextMenuItems }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let onTap {
            Button(action: onTap) {
                Label("Practice this prompt", systemImage: "mic.fill")
            }
        }

        if let onDelete {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Prompt", systemImage: "trash")
            }
        }
    }

    private var categoryColor: Color {
        PromptCategory(rawValue: prompt.category)?.color ?? AppColors.primary
    }
}

// MARK: - Prompt Meta Line

/// Single secondary metadata line — category, difficulty, custom flag —
/// separated by dots instead of stacked colored capsules.
private struct PromptMetaLine: View {
    let prompt: Prompt

    var body: some View {
        HStack(spacing: 6) {
            Text(PromptCategory(rawValue: prompt.category)?.shortName ?? prompt.category)
                .lineLimit(1)

            dot

            Text(prompt.difficulty.displayName)
                .foregroundStyle(AppColors.difficultyColor(prompt.difficulty))

            if prompt.isUserCreated {
                dot
                Text("Custom")
            }

            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var dot: some View {
        Circle()
            .fill(.tertiary)
            .frame(width: 2.5, height: 2.5)
    }
}

// MARK: - Category Short Name

extension PromptCategory {
    /// Compact label for chips and dense rows where `displayName` wraps.
    var shortName: String {
        switch self {
        case .professionalDevelopment: return "Professional"
        case .communicationSkills: return "Communication"
        case .personalGrowth: return "Growth"
        case .problemSolving: return "Problem Solving"
        case .currentEvents: return "Current Events"
        case .quickFire: return "Quick Fire"
        case .debatePersuasion: return "Debate"
        case .interviewPrep: return "Interview"
        case .storytelling: return "Storytelling"
        case .elevatorPitch: return "Pitch"
        case .conversationStarters: return "Conversation"
        case .describeExplain: return "Describe"
        }
    }
}

#Preview {
    NavigationStack {
        PageScrollView {
            AllPromptsView()
                .padding(.horizontal)
        }
        .appBackground(.primary)
    }
    .modelContainer(for: [Prompt.self, Recording.self], inMemory: true)
}

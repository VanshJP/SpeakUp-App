import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AllPromptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Prompt.category) private var allPrompts: [Prompt]
    @Query private var recordings: [Recording]

    @State private var searchText = ""
    @State private var selectedFilter: PromptFilter = .all
    @State private var selectedCategory: PromptCategory?
    @State private var selectedDifficulty: PromptDifficulty?
    @State private var sortMode: PromptSortMode = .category
    @State private var showingAddPrompt = false
    @State private var showingBatchAdd = false
    @State private var showingFileImporter = false
    @State private var importConfirmation: ImportConfirmation?
    @State private var csvService = PromptCSVService()
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var promptToDelete: Prompt?

    let onSelectPrompt: ((Prompt) -> Void)?

    init(onSelectPrompt: ((Prompt) -> Void)? = nil) {
        self.onSelectPrompt = onSelectPrompt
    }

    // MARK: - Computed Data

    private var answeredPromptIDs: Set<String> {
        Set(recordings.compactMap { $0.prompt?.id })
    }

    private var customCount: Int {
        allPrompts.filter(\.isUserCreated).count
    }

    private var filteredPrompts: [Prompt] {
        var prompts = allPrompts

        switch selectedFilter {
        case .all: break
        case .myPrompts: prompts = prompts.filter { $0.isUserCreated }
        case .defaults: prompts = prompts.filter { !$0.isUserCreated }
        case .answered: prompts = prompts.filter { answeredPromptIDs.contains($0.id) }
        case .unanswered: prompts = prompts.filter { !answeredPromptIDs.contains($0.id) }
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

        switch sortMode {
        case .category: prompts.sort { $0.category < $1.category }
        case .alphabetical: prompts.sort { $0.text.localizedCompare($1.text) == .orderedAscending }
        case .difficulty:
            let order: [PromptDifficulty] = [.easy, .medium, .hard]
            prompts.sort { (order.firstIndex(of: $0.difficulty) ?? 0) < (order.firstIndex(of: $1.difficulty) ?? 0) }
        }

        return prompts
    }

    private var groupedPrompts: [(String, [Prompt])] {
        Dictionary(grouping: filteredPrompts, by: \.category)
            .sorted { $0.key < $1.key }
    }

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedDifficulty != nil || sortMode != .category
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppBackground(style: .primary)

            ScrollView {
                VStack(spacing: 16) {
                    statsCard
                    filterChips
                    activeFiltersRow

                    let groups = groupedPrompts
                    if groups.isEmpty {
                        emptyState
                    } else {
                        promptSections(groups)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Prompts")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search prompts...")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                toolbarFilterMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                toolbarAddMenu
            }
        }
        .sheet(isPresented: $showingAddPrompt) {
            AddPromptView()
        }
        .sheet(isPresented: $showingBatchAdd) {
            BatchAddPromptsView()
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

    private var toolbarFilterMenu: some View {
        Menu {
            Section("Export & Import") {
                Button {
                    csvService.shareCSV(prompts: filteredPrompts)
                } label: {
                    Label(
                        hasActiveFilters ? "Export Filtered (\(filteredPrompts.count))" : "Export All Prompts",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(filteredPrompts.isEmpty)

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
            }

            Section("Sort") {
                Picker("Sort", selection: $sortMode) {
                    ForEach(PromptSortMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }
            }

            Section("Category") {
                Button {
                    withAnimation { selectedCategory = nil }
                } label: {
                    HStack {
                        Label("All Categories", systemImage: "square.grid.2x2")
                        if selectedCategory == nil { Spacer(); Image(systemName: "checkmark") }
                    }
                }

                ForEach(PromptCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation { selectedCategory = category }
                    } label: {
                        HStack {
                            Label(category.displayName, systemImage: category.iconName)
                            if selectedCategory == category { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
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

    private var toolbarAddMenu: some View {
        Menu {
            Button {
                showingAddPrompt = true
            } label: {
                Label("Add Single Prompt", systemImage: "plus")
            }

            Button {
                showingBatchAdd = true
            } label: {
                Label("Add Multiple Prompts", systemImage: "text.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 0) {
                PromptStatItem(
                    icon: "text.bubble.fill",
                    value: "\(allPrompts.count)",
                    label: "Total",
                    color: .teal
                )

                promptStatDivider

                PromptStatItem(
                    icon: "checkmark.circle.fill",
                    value: "\(answeredPromptIDs.count)",
                    label: "Answered",
                    color: .green
                )

                promptStatDivider

                PromptStatItem(
                    icon: "circle.dashed",
                    value: "\(allPrompts.count - answeredPromptIDs.count)",
                    label: "Remaining",
                    color: .orange
                )

                promptStatDivider

                PromptStatItem(
                    icon: "person.fill",
                    value: "\(customCount)",
                    label: "Custom",
                    color: .purple
                )
            }
        }
    }

    private var promptStatDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 40)
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
        case .myPrompts: return customCount
        case .defaults: return allPrompts.count - customCount
        case .answered: return answeredPromptIDs.count
        case .unanswered: return allPrompts.count - answeredPromptIDs.count
        }
    }

    // MARK: - Active Filters Row

    @ViewBuilder
    private var activeFiltersRow: some View {
        if hasActiveFilters {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if let category = selectedCategory {
                        activeFilterTag(
                            icon: category.iconName,
                            label: shortCategoryName(category),
                            color: category.color
                        ) {
                            withAnimation { selectedCategory = nil }
                        }
                    }

                    if let difficulty = selectedDifficulty {
                        activeFilterTag(
                            icon: difficultyIcon(difficulty),
                            label: difficulty.displayName,
                            color: difficulty.color
                        ) {
                            withAnimation { selectedDifficulty = nil }
                        }
                    }

                    if sortMode != .category {
                        activeFilterTag(
                            icon: sortMode.icon,
                            label: sortMode.displayName,
                            color: .teal
                        ) {
                            withAnimation { sortMode = .category }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
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

    // MARK: - Prompt Sections

    private func promptSections(_ groups: [(String, [Prompt])]) -> some View {
        LazyVStack(spacing: 16, pinnedViews: .sectionHeaders) {
            ForEach(groups, id: \.0) { category, prompts in
                Section {
                    ForEach(prompts, id: \.id) { prompt in
                        PromptRow(
                            prompt: prompt,
                            isAnswered: answeredPromptIDs.contains(prompt.id),
                            showMicIcon: onSelectPrompt != nil,
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
                } header: {
                    promptSectionHeader(category, prompts: prompts)
                }
            }
        }
    }

    // MARK: - Section Header

    private func promptSectionHeader(_ category: String, prompts: [Prompt]) -> some View {
        let answeredCount = prompts.filter { answeredPromptIDs.contains($0.id) }.count
        return HStack {
            if let cat = PromptCategory(rawValue: category) {
                Image(systemName: cat.iconName)
                    .foregroundStyle(cat.color)
            }
            Text(category)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text("\(answeredCount)/\(prompts.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(.ultraThinMaterial)
                }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
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

    private func shortCategoryName(_ category: PromptCategory) -> String {
        switch category {
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

enum PromptFilter: String, CaseIterable, Identifiable {
    case all
    case myPrompts
    case defaults
    case answered
    case unanswered

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .myPrompts: return "My Prompts"
        case .defaults: return "Default"
        case .answered: return "Answered"
        case .unanswered: return "Unanswered"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .myPrompts: return "person.fill"
        case .defaults: return "tray.full"
        case .answered: return "checkmark.circle"
        case .unanswered: return "circle.dashed"
        }
    }
}

// MARK: - Sort Mode

enum PromptSortMode: String, CaseIterable, Identifiable {
    case category
    case alphabetical
    case difficulty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .category: return "By Category"
        case .alphabetical: return "Alphabetical"
        case .difficulty: return "By Difficulty"
        }
    }

    var icon: String {
        switch self {
        case .category: return "folder"
        case .alphabetical: return "textformat.abc"
        case .difficulty: return "speedometer"
        }
    }
}

// MARK: - Prompt Stat Item

private struct PromptStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

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

// MARK: - Category Chip

struct CategoryChip: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(color.opacity(0.7))
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                        }
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prompt Row

struct PromptRow: View {
    let prompt: Prompt
    var isAnswered: Bool = false
    var showMicIcon: Bool = false
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        let content = GlassCard(tint: categoryColor.opacity(0.05), padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(prompt.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Label(prompt.category, systemImage: categoryIcon)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(categoryColor)
                            .lineLimit(1)

                        DifficultyBadge(difficulty: prompt.difficulty)

                        if prompt.isUserCreated {
                            Text("Custom")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.teal)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule().fill(.teal.opacity(0.15))
                                }
                        }
                    }
                }

                Spacer(minLength: 4)

                if isAnswered {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                } else if onTap != nil {
                    Image(systemName: "mic.fill")
                        .font(.body)
                        .foregroundStyle(.teal)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
        PromptCategory(rawValue: prompt.category)?.color ?? .gray
    }

    private var categoryIcon: String {
        PromptCategory(rawValue: prompt.category)?.iconName ?? "text.bubble"
    }
}

#Preview {
    NavigationStack {
        AllPromptsView()
    }
    .modelContainer(for: [Prompt.self, Recording.self], inMemory: true)
}

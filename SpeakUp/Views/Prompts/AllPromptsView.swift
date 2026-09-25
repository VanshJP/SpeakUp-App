import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @Binding private var searchText: String

    init(
        onSelectPrompt: ((Prompt) -> Void)? = nil,
        searchText: Binding<String>
    ) {
        self.onSelectPrompt = onSelectPrompt
        self._searchText = searchText
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

        if !query.isEmpty {
            prompts = prompts.filter { $0.text.localizedStandardContains(query) }
        }

        prompts.sort { $0.category < $1.category }
        return prompts
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A query or a difficulty turns the landing into a results list. The
    /// category grid can show neither, and used to swallow both: typing
    /// changed nothing on screen.
    private var isNarrowed: Bool {
        !query.isEmpty || selectedDifficulty != nil
    }

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedDifficulty != nil
    }

    // MARK: - Body

    var body: some View {
        let prompts = filteredPrompts

        return ScrollViewReader { proxy in
            screenDecorations(
                VStack(spacing: 16) {
                    InlineSearchField(
                        text: $searchText,
                        prompt: searchPrompt(count: prompts.count),
                        scopes: searchScopes
                    ) {
                        filterMenu(prompts)
                    }
                    .id(Self.topID)

                    // The grid and a category's list fade into each other;
                    // glass never slides.
                    if selectedCategory == nil {
                        VStack(spacing: 16) {
                            filterChips
                            landingContent(prompts)
                        }
                        .transition(.opacity)
                    } else {
                        categoryDetailContent(prompts)
                            .transition(.opacity)
                    }
                }
            )
            // Opening or leaving a category swaps the list in place, and the
            // scroll offset outlived the swap: a card tapped low in the grid
            // opened its list halfway down, pill and first prompts off-screen.
            // The hub owns the scroll view, so this reader scrolls it from
            // inside. Anchoring the field's *bottom* to the viewport's bottom
            // asks for an offset above the content's top, which clamps to the
            // resting top; `.top` would park the field under the pinned
            // section picker.
            .onChange(of: selectedCategory) {
                withAnimation(AppMotion.settle) {
                    proxy.scrollTo(Self.topID, anchor: .bottom)
                }
            }
        }
    }

    private static let topID = "prompts-top"

    private func screenDecorations(_ base: some View) -> some View {
        base
            .task {
                await loadAnsweredPromptIDs()
            }
            .onChange(of: allPrompts.count) { _, _ in
                Task { await loadAnsweredPromptIDs() }
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
                // Nothing new: an Import button here imported nothing.
                if importConfirmation?.newCount == 0 {
                    Button("OK", role: .cancel) { importConfirmation = nil }
                } else {
                    Button("Cancel", role: .cancel) { importConfirmation = nil }
                    Button("Import") { confirmImport() }
                }
            } message: {
                if let confirmation = importConfirmation {
                    Text(confirmation.message)
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
            .alert("Couldn't Import Prompts", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
    }
    // MARK: - Filter / Import Menu

    private func filterMenu(_ prompts: [Prompt]) -> some View {
        Menu {
            Section("Export & Import") {
                Button {
                    csvService.shareCSV(prompts: prompts)
                } label: {
                    // Named for what it exports: a query or a chip narrows
                    // the file as much as a pill does.
                    Label(
                        prompts.count < allPrompts.count ? "Export Filtered (\(prompts.count))" : "Export All Prompts",
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
                            Label(difficulty.displayName, systemImage: difficulty.iconName)
                            if selectedDifficulty == difficulty { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(hasActiveFilters ? AppColors.primary : Color.white.opacity(0.75))
                .symbolVariant(hasActiveFilters ? .fill : .none)
                .headerIconChrome()
        }
        .accessibilityLabel("Filter and import prompts")
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
        // Counted off the library, not subtracted: a take can outlive its
        // prompt (a deleted custom one, a challenge link's), and the
        // subtraction then disagreed with the list the chip opens.
        case .unanswered: return allPrompts.count(where: { !answeredPromptIDs.contains($0.id) })
        case .myPrompts: return customCount
        }
    }

    // MARK: - Search Scopes

    /// The open category and difficulty ride inside the search field as
    /// removable pills (see `SearchScope`), and the count rides in its
    /// placeholder, so opening a category adds no rows above its prompts.
    private var searchScopes: [SearchScope] {
        var scopes: [SearchScope] = []
        if let category = selectedCategory {
            scopes.append(SearchScope(
                title: category.shortName,
                icon: category.iconName,
                tint: category.color,
                removeLabel: "Shows all categories"
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selectedCategory = nil
                }
            })
        }
        if let difficulty = selectedDifficulty {
            scopes.append(SearchScope(
                title: difficulty.displayName,
                tint: difficulty.color,
                removeLabel: "Shows every difficulty"
            ) {
                withAnimation { selectedDifficulty = nil }
            })
        }
        return scopes
    }

    /// A pill already names the scope, so the placeholder shrinks to fit
    /// beside it; a filtered list without one carries its count here - the
    /// count a "40 prompts" label used to take a row for.
    private func searchPrompt(count: Int) -> String {
        if !searchScopes.isEmpty { return "Search" }
        return selectedFilter != .all
            ? "Search \(count) prompt\(count == 1 ? "" : "s")…"
            : "Search prompts…"
    }

    // MARK: - Landing Content (Category-First)

    @ViewBuilder
    private func landingContent(_ prompts: [Prompt]) -> some View {
        if isNarrowed {
            // A search shows results and nothing else. The wheel card steps
            // aside: it spins every difficulty and ignores the query, and it
            // pushed the first result below the fold.
            promptResults(prompts)
        } else {
            spinTheWheelCard

            if selectedFilter == .all {
                categoriesSection
            } else {
                promptResults(prompts)
            }
        }
    }

    // MARK: - Spin the Wheel Card

    private var spinTheWheelCard: some View {
        Button {
            Haptics.medium()
            showingPromptWheel = true
        } label: {
            GlassCard(tint: AppColors.primary.opacity(0.06), padding: 0) {
                VStack(spacing: 0) {
                    PromptWheelTeaser()

                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Spin the wheel")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Land on a random prompt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        // Secondary: this card is a door, not the page's one
                        // white primary. On the card it paints a capsule
                        // rather than stacking glass on glass.
                        GlassButtonLabel(
                            title: "Spin",
                            icon: "arrow.trianglehead.2.clockwise.rotate.90",
                            style: .secondary,
                            size: .small
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .clipShape(.rect(cornerRadius: 20))
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spin the wheel")
        .accessibilityHint("Opens the prompt wheel to land on a random prompt")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Categories Grid

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Categories")

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
                        // The identity chip the Tools grid wears. Its fixed
                        // circle also keeps a flat bolt and a tall pair of
                        // bubbles from giving neighbouring cards two heights.
                        IconChip(icon: category.iconName, tint: color, size: 28)

                        Spacer(minLength: 0)

                        Text("\(done)/\(total)")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }

                    Text(category.shortName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)

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
        // VoiceOver read the glyph, then "3/40", then the name.
        .accessibilityLabel(category.displayName)
        .accessibilityValue("\(done) of \(total) answered")
        .accessibilityHint("Shows this category's prompts")
    }

    // MARK: - Category Detail Content

    private func categoryDetailContent(_ prompts: [Prompt]) -> some View {
        promptResults(prompts)
    }

    /// One plate of rows per category, under that category's name - except
    /// inside a category, where the pill in the field already names it. The
    /// outer stack stays lazy, so Unanswered (most of the library) builds
    /// only the categories on screen.
    @ViewBuilder
    private func promptResults(_ prompts: [Prompt]) -> some View {
        if prompts.isEmpty {
            emptyState
        } else {
            LazyVStack(alignment: .leading, spacing: AppLayout.chapterSpacing) {
                ForEach(categoryGroups(prompts), id: \.category) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        if selectedCategory == nil {
                            GlassSectionHeader(PromptCategory(rawValue: group.category)?.displayName ?? group.category)
                        }

                        GlassRowGroup(dividerInset: 14) {
                            ForEach(group.prompts, id: \.id) { prompt in
                                promptRow(prompt)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Runs of one category, in list order - `filteredPrompts` sorts by it.
    private func categoryGroups(_ prompts: [Prompt]) -> [(category: String, prompts: [Prompt])] {
        var groups: [(category: String, prompts: [Prompt])] = []
        for prompt in prompts {
            if groups.last?.category == prompt.category {
                groups[groups.count - 1].prompts.append(prompt)
            } else {
                groups.append((category: prompt.category, prompts: [prompt]))
            }
        }
        return groups
    }

    // MARK: - Prompt Rows

    private func promptRow(_ prompt: Prompt) -> some View {
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

    // MARK: - Empty State

    /// Each empty list says why and offers the way out: add a first prompt,
    /// or clear the query and difficulty that emptied it. "No custom prompts
    /// yet" used to show whenever My prompts came up empty, even when a
    /// search was hiding the ones you had.
    @ViewBuilder
    private var emptyState: some View {
        Group {
            if selectedFilter == .myPrompts && customCount == 0 {
                EmptyStateCard(
                    icon: "text.badge.plus",
                    title: "No custom prompts yet",
                    message: "Create your first custom prompt to get started.",
                    buttonTitle: "Add prompt",
                    buttonAction: { showingAddPrompt = true }
                )
            } else if isNarrowed {
                EmptyStateCard(
                    icon: "magnifyingglass",
                    title: "No prompts found",
                    message: "Nothing here matches your search or difficulty.",
                    buttonTitle: "Clear filters",
                    buttonAction: { clearFilters() }
                )
            } else {
                EmptyStateCard(
                    icon: "checkmark.circle",
                    title: "Nothing left unanswered",
                    message: "Every prompt here has a take. Pick any from All to go again."
                )
            }
        }
        .padding(.top, 40)
    }

    private func clearFilters() {
        Haptics.light()
        withAnimation {
            searchText = ""
            selectedDifficulty = nil
        }
    }

    // MARK: - Actions

    private func loadAnsweredPromptIDs() async {
        let container = modelContext.container
        let result = await Task.detached(priority: .userInitiated) { () -> (ids: Set<String>, counts: [String: PromptCategoryProgress]) in
            let context = ModelContext(container)
            let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
            let prompts = (try? context.fetch(FetchDescriptor<Prompt>())) ?? []

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
                let parsed = try csvService.parseCSV(from: url)
                let (newItems, dupeCount) = PromptCSVService.removingDuplicates(
                    parsed.prompts,
                    text: { $0.text },
                    existing: allPrompts.map(\.text)
                )
                importConfirmation = ImportConfirmation(
                    data: newItems,
                    duplicateCount: dupeCount,
                    skippedCount: parsed.skipped
                )
            } catch {
                showImportError(error)
            }
        case .failure(let error):
            showImportError(error)
        }
    }

    /// Our own error already says how to fix the file. Anything else - a
    /// file that is not UTF-8 text, one that would not open - gets the same
    /// kind of instruction instead of a system sentence about encodings.
    private func showImportError(_ error: Error) {
        errorMessage = (error as? PromptCSVError)?.errorDescription
            ?? "The file couldn't be read. Save it from your spreadsheet as CSV (UTF-8) and try again."
        showingError = true
        Haptics.warning()
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
        // Land on what was just added. Every import is a custom prompt, and a
        // category, difficulty or query left over from before would hide some.
        withAnimation {
            searchText = ""
            selectedCategory = nil
            selectedDifficulty = nil
            selectedFilter = .myPrompts
        }
    }

}

// MARK: - Import Confirmation

private struct ImportConfirmation {
    let data: [PromptImportData]
    let duplicateCount: Int
    /// Rows the parser dropped for having no prompt text.
    let skippedCount: Int

    var newCount: Int { data.count }

    /// What will be added, then what will not and why.
    var message: String {
        var lines: [String] = []
        if newCount == 0 {
            lines.append(duplicateCount == 1
                ? "That prompt is already in your library."
                : "All \(duplicateCount) prompts are already in your library.")
        } else {
            lines.append("Add \(newCount) prompt\(newCount == 1 ? "" : "s") as custom prompts?")
            if duplicateCount > 0 {
                lines.append("\(duplicateCount) already in your library will be skipped.")
            }
        }
        if skippedCount > 0 {
            lines.append("\(skippedCount) row\(skippedCount == 1 ? "" : "s") had no prompt text.")
        }
        return lines.joined(separator: " ")
    }
}

// MARK: - Prompt Filter Enum

enum PromptFilter: String, CaseIterable, Identifiable {
    case all
    case unanswered
    case myPrompts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .unanswered: return "Unanswered"
        case .myPrompts: return "My prompts"
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

/// One prompt as a row on its category's `GlassRowGroup`. It draws no plate:
/// it pads itself and lights edge to edge on press (`RowPressStyle`); the
/// group owns the surface, the hairlines and the clip. It was a `GlassCard`
/// of its own with a category-coloured stripe, a column of plates that
/// pressed with no feedback at all. The category is not on the row either -
/// the group's header or the field's pill names it.
struct PromptRow: View {
    let prompt: Prompt
    var isAnswered: Bool = false
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                PromptMetaLine(prompt: prompt)
            }

            Spacer(minLength: 4)

            trailingGlyph
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(.rect)

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(RowPressStyle())
                .contextMenu { contextMenuItems }
                .accessibilityValue(isAnswered ? "Answered" : "")
                .accessibilityHint("Starts a take with this prompt")
        } else {
            content
                .contextMenu { contextMenuItems }
                .accessibilityElement(children: .combine)
                .accessibilityValue(isAnswered ? "Answered" : "")
        }
    }

    @ViewBuilder
    private var trailingGlyph: some View {
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
}

// MARK: - Prompt Wheel Teaser

/// The crown of the prompt wheel, drawn into the card that opens it: the same
/// `ArcDial`, display-only, in the wheel's own category order, so the Library
/// shows what Spin does before you press it. It turns two stops the first
/// time it appears - the way a wheel settles - and then holds still.
private struct PromptWheelTeaser: View {
    @State private var position: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var categories: [PromptCategory] { PromptWheelViewModel.categoryOrder }

    var body: some View {
        ArcDial(
            count: categories.count,
            position: position,
            wraps: true,
            step: 30,
            isInteractive: false,
            playsDetents: false,
            height: 150,
            tint: { categories[$0].color },
            glyph: { index in
                Image(systemName: categories[index].iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(categories[index].color)
                    .frame(width: 32, height: 32)
            },
            hub: { EmptyView() }
        )
        // Lift the crown toward the card's top edge; the band above the
        // marker is empty at this height.
        .padding(.top, -14)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, position == 0 else { return }
            withAnimation(.spring(duration: 1.4, bounce: 0.2).delay(0.25)) { position = 2 }
        }
    }
}

// MARK: - Prompt Meta Line

private struct PromptMetaLine: View {
    let prompt: Prompt

    var body: some View {
        HStack(spacing: 6) {
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

// MARK: - Difficulty Icon

extension PromptDifficulty {
    /// The difficulty's glyph in the filter menu and on the add forms' chips.
    var iconName: String {
        switch self {
        case .easy: return "hare"
        case .medium: return "figure.walk"
        case .hard: return "flame"
        }
    }
}

#Preview {
    NavigationStack {
        PageScrollView {
            AllPromptsView(searchText: .constant(""))
                .padding(.horizontal)
        }
        .appBackground(.primary)
    }
    .modelContainer(for: [Prompt.self, Recording.self], inMemory: true)
}

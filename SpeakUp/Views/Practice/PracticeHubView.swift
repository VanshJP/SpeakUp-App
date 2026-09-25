import SwiftUI
import SwiftData

struct PracticeHubView: View {
    @State private var selectedSection: PracticeSection = .prompts
    @State private var promptsSearchText = ""
    @State private var storiesSearchText = ""
    @State private var toolsSearchText = ""
    @State private var selectedStory: Story?
    @State private var showingAddPrompt = false
    @State private var showingBatchAdd = false
    @State private var showingNewStory = false
    @State private var compareRoute: CompareRoute?

    // `LibraryTool` used to sit here purely to map four cases onto four
    // `PracticeToolKind` cases. `PracticeToolKind.practiceTools` is that list,
    // and routes now carry an optional focus so the outcome browser can push a
    // tool page already narrowed to what you picked.

    let onSelectPrompt: (Prompt) -> Void
    var onStartStoryPractice: ((Story, RecordingDuration) -> Void)? = nil
    var onSendToWarmUp: ((Story) -> Void)? = nil
    var onSendToDrill: ((Story) -> Void)? = nil
    var onShowBeforeAfter: (() -> Void)? = nil
    var onShowJournalExport: (() -> Void)? = nil
    var onShowGoals: (() -> Void)? = nil
    var storiesViewModel: StoriesViewModel

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PageScrollView {
                LazyVStack(spacing: AppLayout.listSpacing, pinnedViews: [.sectionHeaders]) {
                    Section {
                        switch selectedSection {
                        case .prompts:
                            AllPromptsView(
                                onSelectPrompt: onSelectPrompt,
                                searchText: $promptsSearchText
                            )
                            .transition(.identity)
                        case .stories:
                            StoriesListView(
                                viewModel: storiesViewModel,
                                selectedStory: $selectedStory,
                                searchText: $storiesSearchText,
                                onStartPractice: onStartStoryPractice,
                                onSendToWarmUp: onSendToWarmUp,
                                onSendToDrill: onSendToDrill
                            )
                            .transition(.identity)
                        case .tools:
                            toolsLanding
                                .transition(.identity)
                        }

                        Color.clear.frame(height: 88) // FAB breathing room
                    } header: {
                        pinnedSectionPicker
                    }
                }
                .padding(.top, 4)
                .pageContentInsets()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            floatingActionButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: storiesSearchText) { _, newValue in
            storiesViewModel.setSearch(newValue)
        }
        .navigationDestination(for: PracticeToolRoute.self) { route in
            toolDetail(route)
                .restoresNavigationBar()
        }
        .navigationDestination(for: PracticeFocus.self) { focus in
            PracticeFocusDetailView(focus: focus)
                .restoresNavigationBar()
        }
        .navigationDestination(for: PracticeImproveRoute.self) { _ in
            PracticeImproveListView()
                .restoresNavigationBar()
        }
        .navigationDestination(for: WordLibraryRoute.self) { _ in
            WordLibraryView()
                .restoresNavigationBar()
        }
        .navigationDestination(item: $selectedStory) { story in
            StoryDetailView(
                story: story,
                viewModel: storiesViewModel,
                onStartPractice: onStartStoryPractice,
                onSendToWarmUp: onSendToWarmUp,
                onSendToDrill: onSendToDrill
            )
            .restoresNavigationBar()
        }
        .navigationDestination(item: $compareRoute) { _ in
            ComparisonView()
                .restoresNavigationBar()
        }
        .sheet(isPresented: $showingAddPrompt) {
            AddPromptView()
        }
        .sheet(isPresented: $showingBatchAdd) {
            BatchAddPromptsView()
        }
        .sheet(isPresented: $showingNewStory) {
            NavigationStack {
                StoryEditorView(
                    viewModel: storiesViewModel,
                    existingStory: nil,
                    initialFolderId: currentStoryFolderId,
                    // A new story opens on its own page, where Practice,
                    // Warm up and Drill live - the editor sheet can't start them.
                    onCreated: { selectedStory = $0 }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Tools

    /// Count only. The duration range moved into `PracticeToolKind.format`,
    /// which the card prints underneath - printing it twice was how the old
    /// meta line ended up saying "20s-1 min" next to "15-60s".
    private func meta(for tool: PracticeToolKind) -> String {
        let count: Int
        switch tool {
        case .warmUp: count = DefaultWarmUps.all.count
        case .drills: count = DrillMode.allCases.count
        case .readAloud: count = DefaultReadAloudPassages.all.count
        case .calm: count = DefaultConfidenceExercises.all.count
        case .learn: count = 0
        }
        return "\(count) \(tool.itemNoun)\(count == 1 ? "" : "s")"
    }

    private var toolsCatalog: [PracticeToolKind] { PracticeToolKind.practiceTools }

    private var toolsLanding: some View {
        let query = toolsSearchText.trimmingCharacters(in: .whitespaces)
        let visiblePractice = query.isEmpty
            ? toolsCatalog
            : toolsCatalog.filter {
                $0.title.localizedStandardContains(query)
                    || $0.outcome.localizedStandardContains(query)
                    || $0.bestFor.localizedStandardContains(query)
                    || $0.format.localizedStandardContains(query)
            }
        let visibleFocuses = query.isEmpty
            ? PracticeToolKind.coveredFocuses
            : PracticeToolKind.coveredFocuses.filter {
                $0.title.localizedStandardContains(query)
                    || $0.shortTitle.localizedStandardContains(query)
                    || $0.promise.localizedStandardContains(query)
            }
        let visibleReview = query.isEmpty
            ? ReviewToolKind.allCases
            : ReviewToolKind.allCases.filter {
                $0.title.localizedStandardContains(query)
                    || $0.outcome.localizedStandardContains(query)
                    || $0.bestFor.localizedStandardContains(query)
            }
        // Two characters minimum: a one-letter query matches "words" and
        // every other row on the page, which is not a search result.
        let matchesWordLibrary = query.count >= 2
            && "words dictionary vocabulary definitions lexicon".localizedStandardContains(query)
        // The exercises themselves, by name - "box breathing", "impromptu",
        // "tongue twister" used to find nothing. Same two-letter floor.
        let visibleItems = query.count >= 2 ? PracticeToolKind.items(matching: query) : []

        return VStack(alignment: .leading, spacing: 20) {
            InlineSearchField(text: $toolsSearchText, prompt: "Search tools…") {
                EmptyView()
            }

            if visiblePractice.isEmpty && visibleItems.isEmpty && visibleReview.isEmpty
                && visibleFocuses.isEmpty && !matchesWordLibrary {
                EmptyStateCard(
                    icon: "magnifyingglass",
                    title: "No tools match",
                    message: "Nothing here matches \"\(query)\". Try a different search.",
                    buttonTitle: "Clear search",
                    buttonAction: { toolsSearchText = "" }
                )
            } else {

                if !visiblePractice.isEmpty {
                    toolGrid(title: "Practice") {
                        ForEach(visiblePractice) { tool in
                            NavigationLink(value: PracticeToolRoute(tool: tool)) {
                                ToolCategoryCardLabel(
                                    icon: tool.icon,
                                    title: tool.title,
                                    meta: meta(for: tool),
                                    detail: tool.format,
                                    tint: tool.color
                                )
                            }
                            .buttonStyle(GlassPressStyle())
                            .accessibilityLabel(
                                ToolCategoryCardLabel.voiceOverLabel(
                                    title: tool.title,
                                    detail: tool.outcome,
                                    meta: meta(for: tool),
                                    secondary: tool.format
                                )
                            )
                            .accessibilityHint(tool.bestFor)
                        }
                    }
                }

                if !visibleItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GlassSectionHeader("Exercises")

                        GlassRowGroup(dividerInset: PracticeLinkRowLabel.dividerInset) {
                            ForEach(visibleItems) { item in
                                exerciseResultRow(item)
                            }
                        }
                    }
                }

                // The outcome axis, one row rather than the header, caption and
                // eight rows it used to be. Both were doors to the same forty
                // exercises and this was the longer one; the axis itself lives
                // on inside every tool page, which groups by it. Searching is
                // different - a query for "fillers" should land on the outcome,
                // not on a row that promises to have one.
                if query.isEmpty {
                    // Two rows that push, so one plate - not two cards.
                    GlassRowGroup(dividerInset: PracticeLinkRowLabel.dividerInset) {
                        PracticeImproveEntryRow()
                        wordsEntryRow
                    }
                } else if !visibleFocuses.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GlassSectionHeader("Improve")

                        GlassRowGroup(dividerInset: PracticeLinkRowLabel.dividerInset) {
                            ForEach(visibleFocuses) { focus in
                                PracticeFocusRow(focus: focus)
                            }
                        }
                    }
                }

                if matchesWordLibrary {
                    GlassRowGroup {
                        wordsEntryRow
                    }
                }

                if !visibleReview.isEmpty {
                    toolGrid(title: "Review") {
                        ForEach(visibleReview) { tool in
                            // `outcome` fills the same slot the practice
                            // cards give to `format`, so both grids are one
                            // matrix instead of two card shapes.
                            ToolCategoryCard(
                                icon: tool.icon,
                                title: tool.title,
                                meta: tool.meta,
                                detail: tool.outcome,
                                tint: tool.color
                            ) {
                                openReviewTool(tool)
                            }
                            .accessibilityHint(tool.bestFor)
                        }
                    }
                }
            }
        }
    }

    /// A search hit pushes its tool page, scrolled to the item's group.
    private func exerciseResultRow(_ item: PracticeToolItem) -> some View {
        NavigationLink(value: PracticeToolRoute(tool: item.tool, focus: item.focus)) {
            PracticeLinkRowLabel(
                icon: item.tool.icon,
                tint: item.tool.color,
                title: item.title,
                meta: "\(item.tool.title) · \(item.focus.title)"
            )
        }
        .buttonStyle(RowPressStyle())
    }

    /// The Words entry as a row on the entry group - a card of its own on
    /// the group's plate would be glass on glass.
    private var wordsEntryRow: some View {
        let summary = "\(DefaultVocabLexicon.entries.count) words"
        return NavigationLink(value: WordLibraryRoute()) {
            PracticeLinkRowLabel(
                icon: "character.book.closed.fill",
                tint: AppColors.categorySage,
                title: "Words",
                subtitle: "Look up a word, keep the ones worth using",
                meta: summary
            )
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("Words. Look up a word, keep the ones worth using. \(summary).")
    }

    private func toolGrid<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                content()
            }
        }
    }

    private func openReviewTool(_ tool: ReviewToolKind) {
        switch tool {
        case .compare:
            compareRoute = CompareRoute()
        case .listenBack:
            onShowBeforeAfter?()
        case .goals:
            onShowGoals?()
        case .journal:
            onShowJournalExport?()
        }
    }

    /// A tool opens as a real push - the same navigation motion and the same
    /// system Back button as a story or Compare. It used to slide in and out of
    /// the scroll view under `withAnimation`, behind a hand-rolled "All tools"
    /// pill, which is why entering a tool felt unlike entering anything else in
    /// the app. `ToolPage(.pushed)` supplies the inline title and the outcome
    /// line the old wrapper drew by hand.
    @ViewBuilder
    private func toolDetail(_ route: PracticeToolRoute) -> some View {
        switch route.tool {
        case .warmUp:
            WarmUpListView(presentation: .pushed, initialFocus: route.focus)
        case .drills:
            DrillSelectionView(presentation: .pushed, initialFocus: route.focus)
        case .readAloud:
            ReadAloudSelectionView(presentation: .pushed, initialFocus: route.focus)
        case .calm:
            ConfidenceToolsView(presentation: .pushed, initialFocus: route.focus)
        case .learn:
            // Learn is a tab, not a tool page. Unreachable via `practiceTools`.
            EmptyView()
        }
    }

    // MARK: - Floating Action Button

    @ViewBuilder
    private var floatingActionButton: some View {
        switch selectedSection {
        case .prompts:
            Menu {
                Button {
                    Haptics.light()
                    showingAddPrompt = true
                } label: {
                    Label("Add Single Prompt", systemImage: "plus")
                }

                Button {
                    Haptics.light()
                    showingBatchAdd = true
                } label: {
                    Label("Add Multiple Prompts", systemImage: "text.badge.plus")
                }
            } label: {
                fabLabel("Add prompt")
            }
        case .stories:
            Button {
                Haptics.heavy()
                showingNewStory = true
            } label: {
                fabLabel("New story")
            }
            .buttonStyle(GlassPressStyle())
        case .tools:
            EmptyView()
        }
    }

    /// Says what it adds: a bare "+" meant a prompt on one section and a
    /// story on the next, and was a hand-rolled white disc beside the
    /// primary style that owns that fill (ui-design-system rule 4).
    private func fabLabel(_ title: String) -> some View {
        GlassButtonLabel(title: title, icon: "plus", style: .primary)
    }

    // MARK: - Helpers

    private var currentStoryFolderId: UUID? {
        if case .folder(let id) = storiesViewModel.folderSelection { return id }
        return nil
    }

    // MARK: - Pinned Section Picker

    private var pinnedSectionPicker: some View {
        PinnedPageHeader {
            sectionPicker
        } accessory: {
            EmptyView()
        }
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        SectionPicker(
            sections: PracticeSection.allCases,
            selection: $selectedSection,
            label: { $0.label },
            icon: { $0.icon }
        )
    }
}

// MARK: - Practice Section Enum

enum PracticeSection: String, CaseIterable, Identifiable {
    case prompts
    case stories
    case tools

    var id: String { rawValue }

    var label: String {
        switch self {
        case .prompts: return "Prompts"
        case .stories: return "Stories"
        case .tools: return "Tools"
        }
    }

    var icon: String {
        switch self {
        case .prompts: return "text.bubble.fill"
        case .stories: return "text.book.closed.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        }
    }
}

private struct CompareRoute: Hashable, Identifiable {
    let id = UUID()
}

#Preview {
    NavigationStack {
        PracticeHubView(
            onSelectPrompt: { _ in },
            storiesViewModel: StoriesViewModel()
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserSettings.self], inMemory: true)
}

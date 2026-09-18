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
                    onStartPractice: onStartStoryPractice,
                    onSendToWarmUp: onSendToWarmUp,
                    onSendToDrill: onSendToDrill
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Tools

    /// Count only. The duration range moved into `PracticeToolKind.format`,
    /// which the card prints underneath — printing it twice was how the old
    /// meta line ended up saying "20s–1 min" next to "15–60s".
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
            ? PracticeFocus.allCases
            : PracticeFocus.allCases.filter {
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

        return VStack(alignment: .leading, spacing: 20) {
            InlineSearchField(text: $toolsSearchText, prompt: "Search tools…") {
                EmptyView()
            }

            if visiblePractice.isEmpty && visibleReview.isEmpty && visibleFocuses.isEmpty {
                EmptyStateCard(
                    icon: "magnifyingglass",
                    title: "No tools match",
                    message: "Nothing here matches \"\(query)\". Try a different search."
                )
            } else {
                // Outcome first. The four tools are formats, and which format
                // you want is a second-order question — "I mumble" should not
                // require knowing that mumbling is filed under Warm-Ups,
                // Read Aloud, or both.
                if !visibleFocuses.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GlassSectionHeader("Improve", icon: "target")

                        Text("Pick what you want to change. Every exercise that trains it, in one place.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 10) {
                            ForEach(visibleFocuses) { focus in
                                PracticeFocusRow(focus: focus)
                            }
                        }
                    }
                }

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

                if !visibleReview.isEmpty {
                    toolGrid(title: "Review") {
                        ForEach(visibleReview) { tool in
                            ToolCategoryCard(
                                icon: tool.icon,
                                title: tool.title,
                                meta: tool.meta,
                                tint: tool.color,
                                accessibilityDetail: tool.outcome
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

    private func toolGrid<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title, icon: title == "Review" ? "ellipsis.circle" : "wrench.and.screwdriver")

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

    /// A tool opens as a real push — the same navigation motion and the same
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
                fabLabel
            }
            .accessibilityLabel("Add prompt")
        case .stories:
            Button {
                Haptics.heavy()
                showingNewStory = true
            } label: {
                fabLabel
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("New story")
        case .tools:
            EmptyView()
        }
    }

    private var fabLabel: some View {
        Image(systemName: "plus")
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
            .frame(width: 58, height: 58)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.94))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
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

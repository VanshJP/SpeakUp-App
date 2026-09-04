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
    /// Non-nil pushes Compare from Library → Tools → Review.
    @State private var compareRoute: CompareRoute?

    // Practice tools — same grammar as Prompts: category grid → in-place
    // detail (filters + items). Today's quick tiles still present sheets.
    private enum LibraryTool: String, Identifiable, CaseIterable {
        case warmUps
        case drills
        case readAloud
        case confidence

        var id: String { rawValue }

        var kind: PracticeToolKind {
            switch self {
            case .warmUps: return .warmUp
            case .drills: return .drills
            case .readAloud: return .readAloud
            case .confidence: return .calm
            }
        }
    }

    @State private var selectedTool: LibraryTool?

    let onSelectPrompt: (Prompt) -> Void
    var onStartStoryPractice: ((Story) -> Void)? = nil
    var onSendToWarmUp: ((Story) -> Void)? = nil
    var onSendToDrill: ((Story) -> Void)? = nil
    var onShowBeforeAfter: (() -> Void)? = nil
    var onShowJournalExport: (() -> Void)? = nil
    var onShowGoals: (() -> Void)? = nil
    var storiesViewModel: StoriesViewModel

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()

            PageScrollView {
                LazyVStack(spacing: AppLayout.listSpacing, pinnedViews: [.sectionHeaders]) {
                    Section {
                        // Each section owns a topBarTrailing toolbar item. A
                        // crossfade keeps the outgoing section alive for the
                        // animation, so two filter buttons render at once —
                        // swap instantly instead. The picker pill still slides.
                        switch selectedSection {
                        case .prompts:
                            AllPromptsView(
                                onSelectPrompt: onSelectPrompt,
                                searchText: promptsSearchText
                            )
                            .transition(.identity)
                        case .stories:
                            StoriesListView(
                                viewModel: storiesViewModel,
                                selectedStory: $selectedStory,
                                onStartPractice: onStartStoryPractice,
                                onSendToWarmUp: onSendToWarmUp,
                                onSendToDrill: onSendToDrill
                            )
                            .transition(.identity)
                        case .tools:
                            toolsSection
                                .transition(.identity)
                        }

                        Color.clear.frame(height: 88) // FAB breathing room
                    } header: {
                        pinnedSectionPicker
                    }
                }
                .pageContentInsets()
            }
            .scrollIndicators(.hidden)

            floatingActionButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        // No root title — the tab bar already says Library, and the pinned
        // SectionPicker names the section. A nav title (large or inline) only
        // stacked chrome above the picker; trailing filter/sort stay.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: activeSearchText, prompt: searchPrompt)
        .onChange(of: storiesSearchText) { _, newValue in
            storiesViewModel.setSearch(newValue)
        }
        .onChange(of: selectedSection) { _, _ in
            // Leaving Tools drops the in-place drill-down so returning lands
            // on the category grid, matching Prompts' category reset feel.
            selectedTool = nil
        }
        .navigationDestination(item: $selectedStory) { story in
            StoryDetailView(
                story: story,
                viewModel: storiesViewModel,
                onStartPractice: onStartStoryPractice,
                onSendToWarmUp: onSendToWarmUp,
                onSendToDrill: onSendToDrill
            )
        }
        .navigationDestination(item: $compareRoute) { _ in
            ComparisonView()
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

    /// "4 exercises · 1–3 min" — count plus the real time range, so a tile says
    /// what it costs before you tap it. Computed from the seed data rather than
    /// written down, so it can't drift when exercises are added.
    private static func countMeta(_ count: Int, _ noun: String, seconds: [Int]) -> String {
        let countText = "\(count) \(noun)\(count == 1 ? "" : "s")"
        guard let low = seconds.min(), let high = seconds.max(), low > 0 else { return countText }

        func format(_ value: Int) -> String {
            value < 60 ? "\(value)s" : "\(Int((Double(value) / 60).rounded())) min"
        }

        let range = low == high ? format(low) : "\(format(low))–\(format(high))"
        return "\(countText) · \(range)"
    }

    private func meta(for tool: LibraryTool) -> String {
        switch tool {
        case .warmUps:
            return Self.countMeta(
                DefaultWarmUps.all.count,
                "exercise",
                seconds: DefaultWarmUps.all.map(\.durationSeconds)
            )
        case .drills:
            return Self.countMeta(
                DrillMode.allCases.count,
                "mode",
                seconds: DrillMode.allCases.map(\.defaultDurationSeconds)
            )
        case .readAloud:
            return "\(DefaultReadAloudPassages.all.count) passages · scored"
        case .confidence:
            return Self.countMeta(
                DefaultConfidenceExercises.all.count,
                "exercise",
                seconds: DefaultConfidenceExercises.all.map { $0.durationMinutes * 60 }
            )
        }
    }

    private var toolsCatalog: [LibraryTool] { LibraryTool.allCases }

    private var toolsSection: some View {
        Group {
            if let selectedTool {
                toolDetail(selectedTool)
                    // Detail enters/exits from the trailing edge — same grammar
                    // as a NavigationStack push. The old asymmetric pair used
                    // opposite edges for removal, so forward looked like back.
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                toolsLanding
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
    }

    /// Category grid — practice tools, then review tools. Same card recipe.
    private var toolsLanding: some View {
        let query = toolsSearchText.trimmingCharacters(in: .whitespaces)
        let visiblePractice = query.isEmpty
            ? toolsCatalog
            : toolsCatalog.filter {
                $0.kind.title.localizedStandardContains(query)
                    || $0.kind.outcome.localizedStandardContains(query)
                    || $0.kind.bestFor.localizedStandardContains(query)
            }
        let visibleReview = query.isEmpty
            ? ReviewToolKind.allCases
            : ReviewToolKind.allCases.filter {
                $0.title.localizedStandardContains(query)
                    || $0.outcome.localizedStandardContains(query)
                    || $0.bestFor.localizedStandardContains(query)
            }

        return VStack(alignment: .leading, spacing: 20) {
            if query.isEmpty {
                Text("Practice Tools")
                    .eyebrowStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Warm up, drill, read aloud, or settle nerves before a take.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if visiblePractice.isEmpty && visibleReview.isEmpty {
                EmptyStateCard(
                    icon: "magnifyingglass",
                    title: "No tools match",
                    message: "Nothing here matches \"\(query)\". Try a different search."
                )
            } else {
                if !visiblePractice.isEmpty {
                    toolGrid(title: query.isEmpty ? nil : "Practice") {
                        ForEach(visiblePractice) { tool in
                            ToolCategoryCard(
                                icon: tool.kind.icon,
                                title: tool.kind.title,
                                meta: meta(for: tool),
                                tint: tool.kind.color,
                                accessibilityDetail: tool.kind.outcome
                            ) {
                                withAnimation(AppMotion.settle) {
                                    selectedTool = tool
                                }
                            }
                            .accessibilityHint(tool.kind.bestFor)
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
        title: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                GlassSectionHeader(title, icon: title == "Review" ? "ellipsis.circle" : "wrench.and.screwdriver")
            }

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

    @ViewBuilder
    private func toolDetail(_ tool: LibraryTool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassButton(
                title: "All tools",
                icon: "chevron.left",
                style: .secondary,
                size: .small
            ) {
                Haptics.light()
                withAnimation(AppMotion.settle) {
                    selectedTool = nil
                }
            }
            .accessibilityHint("Returns to the tools list")

            Text(tool.kind.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(tool.kind.outcome)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch tool {
            case .warmUps:
                WarmUpListView(presentation: .embedded)
            case .drills:
                DrillSelectionView(presentation: .embedded)
            case .readAloud:
                ReadAloudSelectionView(presentation: .embedded)
            case .confidence:
                ConfidenceToolsView(presentation: .embedded)
            }
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

    // MARK: - Search Routing

    private var activeSearchText: Binding<String> {
        switch selectedSection {
        case .prompts: return $promptsSearchText
        case .stories: return $storiesSearchText
        case .tools: return $toolsSearchText
        }
    }

    private var searchPrompt: String {
        switch selectedSection {
        case .prompts: return "Search prompts…"
        case .stories: return "Search stories…"
        case .tools: return "Search tools…"
        }
    }

    // MARK: - Helpers

    private var currentStoryFolderId: UUID? {
        if case .folder(let id) = storiesViewModel.folderSelection { return id }
        return nil
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

/// Stable identity for the Compare push from Library → Tools.
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

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

    // Practice tools — pushed as full pages from here (Library is where you
    // browse, so a tool gets the whole screen). Today's quick tiles and the
    // focus card keep presenting them as sheets.
    private enum LibraryTool: String, Identifiable {
        case warmUps
        case drills
        case readAloud
        case confidence

        var id: String { rawValue }
    }

    @State private var activeTool: LibraryTool?

    let onSelectPrompt: (Prompt) -> Void
    var onStartStoryPractice: ((Story) -> Void)? = nil
    var onSendToWarmUp: ((Story) -> Void)? = nil
    var onSendToDrill: ((Story) -> Void)? = nil
    var storiesViewModel: StoriesViewModel

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()

            PageScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
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
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            floatingActionButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: activeSearchText, prompt: searchPrompt)
        .onChange(of: storiesSearchText) { _, newValue in
            storiesViewModel.setSearch(newValue)
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
        .navigationDestination(item: $activeTool) { tool in
            switch tool {
            case .warmUps:
                WarmUpListView(isPushed: true)
            case .drills:
                DrillSelectionView(isPushed: true)
            case .readAloud:
                ReadAloudSelectionView(isPushed: true)
            case .confidence:
                ConfidenceToolsView(isPushed: true)
            }
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

    /// "4 exercises · 1–3 min" — count plus the real time range, so a row says
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

    /// Browsable catalog of every prep surface. Copy comes from
    /// `PracticeToolKind` so Today tiles and these rows tell the same story.
    private var tools: [PracticeTool] {
        [
            PracticeTool(
                kind: .warmUp,
                meta: Self.countMeta(
                    DefaultWarmUps.all.count,
                    "exercise",
                    seconds: DefaultWarmUps.all.map(\.durationSeconds)
                )
            ) { activeTool = .warmUps },
            PracticeTool(
                kind: .drills,
                meta: Self.countMeta(
                    DrillMode.allCases.count,
                    "mode",
                    seconds: DrillMode.allCases.map(\.defaultDurationSeconds)
                )
            ) { activeTool = .drills },
            PracticeTool(
                kind: .readAloud,
                meta: "\(DefaultReadAloudPassages.all.count) passages · scored"
            ) { activeTool = .readAloud },
            PracticeTool(
                kind: .calm,
                meta: Self.countMeta(
                    DefaultConfidenceExercises.all.count,
                    "exercise",
                    seconds: DefaultConfidenceExercises.all.map { $0.durationMinutes * 60 }
                )
            ) { activeTool = .confidence }
        ]
    }

    private var toolsSection: some View {
        let query = toolsSearchText.trimmingCharacters(in: .whitespaces)
        let visible = query.isEmpty
            ? tools
            : tools.filter {
                $0.kind.title.localizedStandardContains(query)
                    || $0.kind.outcome.localizedStandardContains(query)
                    || $0.kind.bestFor.localizedStandardContains(query)
            }

        return VStack(alignment: .leading, spacing: 14) {
            if query.isEmpty {
                Text("Practice Tools")
                    .eyebrowStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)

                toolsIntro
            }

            if visible.isEmpty {
                // Search that matches nothing used to render a silent blank
                // scroll, which reads as a broken screen rather than a result.
                EmptyStateCard(
                    icon: "magnifyingglass",
                    title: "No tools match",
                    message: "Nothing here matches \"\(query)\". Try a different search."
                )
            } else {
                ForEach(visible) { tool in
                    toolRow(tool)
                }
            }
        }
    }

    /// Explains how Tools differ from Prompts and Stories so the third Library
    /// segment is not just another list of cards with icons.
    private var toolsIntro: some View {
        GlassCard(tint: AppColors.primary.opacity(0.06), padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prep and targeted reps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Prompts and Stories are what you speak. Tools are how you get ready — warm the voice, drill one weakness, settle nerves, or score a read-aloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toolRow(_ tool: PracticeTool) -> some View {
        Button {
            Haptics.medium()
            tool.action()
        } label: {
            GlassCard(cornerRadius: 16, tint: tool.kind.color.opacity(0.06), padding: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: tool.kind.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tool.kind.color)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle().fill(tool.kind.color.opacity(0.18))
                        }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(tool.kind.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(tool.kind.outcome)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(tool.kind.bestFor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(tool.meta)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("\(tool.kind.title). \(tool.kind.outcome). \(tool.meta)")
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

// MARK: - Practice Tool

private struct PracticeTool: Identifiable {
    let kind: PracticeToolKind
    /// Count + time cost. The line that makes a mixed-type list navigable.
    let meta: String
    let action: () -> Void

    var id: String { kind.id }
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

#Preview {
    NavigationStack {
        PracticeHubView(
            onSelectPrompt: { _ in },
            storiesViewModel: StoriesViewModel()
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserSettings.self], inMemory: true)
}

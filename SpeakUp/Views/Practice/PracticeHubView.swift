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

    // Practice tools — presented locally; each is a self-contained sheet.
    @State private var showingWarmUps = false
    @State private var showingDrills = false
    @State private var showingReadAloud = false
    @State private var showingConfidence = false

    let onSelectPrompt: (Prompt) -> Void
    var onStartStoryPractice: ((Story) -> Void)? = nil
    var onSendToWarmUp: ((Story) -> Void)? = nil
    var onSendToDrill: ((Story) -> Void)? = nil
    var storiesViewModel: StoriesViewModel

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()

            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        switch selectedSection {
                        case .prompts:
                            AllPromptsView(
                                onSelectPrompt: onSelectPrompt,
                                searchText: promptsSearchText
                            )
                            .transition(.opacity)
                        case .stories:
                            StoriesListView(
                                viewModel: storiesViewModel,
                                selectedStory: $selectedStory,
                                onStartPractice: onStartStoryPractice,
                                onSendToWarmUp: onSendToWarmUp,
                                onSendToDrill: onSendToDrill
                            )
                            .transition(.opacity)
                        case .tools:
                            toolsSection
                                .transition(.opacity)
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
        .sheet(isPresented: $showingWarmUps) {
            WarmUpListView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDrills) {
            DrillSelectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReadAloud) {
            ReadAloudSelectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingConfidence) {
            ConfidenceToolsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Tools

    /// The practice tools used to live only behind six small tiles on Today.
    /// They belong in the Library — this is the browsable list of everything
    /// you can practice with.
    private var tools: [PracticeTool] {
        [
            PracticeTool(icon: "wind", color: AppColors.toolWarmUp, title: "Warm-Ups",
                         subtitle: "Breathing, tongue twisters, vocal reps",
                         meta: Self.countMeta(DefaultWarmUps.all.count, "exercise",
                                              seconds: DefaultWarmUps.all.map(\.durationSeconds))) { showingWarmUps = true },
            PracticeTool(icon: "bolt.fill", color: AppColors.toolDrill, title: "Drills",
                         subtitle: "Short reps against one weakness",
                         meta: Self.countMeta(DrillMode.allCases.count, "mode",
                                              seconds: DrillMode.allCases.map(\.defaultDurationSeconds))) { showingDrills = true },
            PracticeTool(icon: "text.book.closed", color: AppColors.toolReadAloud, title: "Read Aloud",
                         subtitle: "Passages scored for pronunciation",
                         meta: "\(DefaultReadAloudPassages.all.count) passages · scored") { showingReadAloud = true },
            PracticeTool(icon: "heart.fill", color: AppColors.toolCalm, title: "Calm",
                         subtitle: "Settle nerves before you speak",
                         meta: Self.countMeta(DefaultConfidenceExercises.all.count, "exercise",
                                              seconds: DefaultConfidenceExercises.all.map { $0.durationMinutes * 60 })) { showingConfidence = true }
        ]
    }

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

    private var toolsSection: some View {
        let query = toolsSearchText.trimmingCharacters(in: .whitespaces)
        let visible = query.isEmpty
            ? tools
            : tools.filter {
                $0.title.localizedStandardContains(query) || $0.subtitle.localizedStandardContains(query)
            }

        return VStack(spacing: 12) {
            ForEach(visible) { tool in
                toolRow(tool)
            }
        }
    }

    private func toolRow(_ tool: PracticeTool) -> some View {
        Button {
            Haptics.medium()
            tool.action()
        } label: {
            GlassCard(cornerRadius: 16, padding: 14) {
                HStack(spacing: 14) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tool.color)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tool.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(tool.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(tool.meta)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
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
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    /// Count + time cost. The line that makes a mixed-type list navigable.
    let meta: String
    let action: () -> Void

    var id: String { title }
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

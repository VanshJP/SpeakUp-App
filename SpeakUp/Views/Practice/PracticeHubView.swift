import SwiftUI
import SwiftData

struct PracticeHubView: View {
    @State private var selectedSection: PracticeSection = .prompts
    @State private var promptsSearchText = ""
    @State private var storiesSearchText = ""
    @State private var selectedStory: Story?
    @State private var showingAddPrompt = false
    @State private var showingBatchAdd = false
    @State private var showingNewStory = false

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
                        case .journal:
                            StoriesListView(
                                viewModel: storiesViewModel,
                                selectedStory: $selectedStory,
                                onStartPractice: onStartStoryPractice,
                                onSendToWarmUp: onSendToWarmUp,
                                onSendToDrill: onSendToDrill
                            )
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
        case .journal:
            Button {
                Haptics.heavy()
                showingNewStory = true
            } label: {
                fabLabel
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("New note")
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
        case .journal: return $storiesSearchText
        }
    }

    private var searchPrompt: String {
        switch selectedSection {
        case .prompts: return "Search prompts..."
        case .journal: return "Search notes…"
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
    case journal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .prompts: return "Prompts"
        case .journal: return "Journal"
        }
    }

    var icon: String {
        switch self {
        case .prompts: return "text.bubble.fill"
        case .journal: return "text.book.closed.fill"
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

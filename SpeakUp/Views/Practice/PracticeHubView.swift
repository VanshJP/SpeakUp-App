import SwiftUI
import SwiftData

struct PracticeHubView: View {
    @State private var selectedSection: PracticeSection = .prompts

    let onSelectPrompt: (Prompt) -> Void
    var onStartStoryPractice: ((Story) -> Void)? = nil
    var onSendToWarmUp: ((Story) -> Void)? = nil
    var onSendToDrill: ((Story) -> Void)? = nil
    var storiesViewModel: StoriesViewModel

    // MARK: - Body

    var body: some View {
        ZStack {
            AppBackground()

            ZStack {
                switch selectedSection {
                case .prompts:
                    AllPromptsView(onSelectPrompt: onSelectPrompt) {
                        pinnedSectionPicker
                    }
                    .transition(.opacity)
                case .journal:
                    StoriesListView(
                        viewModel: storiesViewModel,
                        onStartPractice: onStartStoryPractice,
                        onSendToWarmUp: onSendToWarmUp,
                        onSendToDrill: onSendToDrill
                    ) {
                        pinnedSectionPicker
                    }
                    .transition(.opacity)
                }
            }
        }
        .navigationTitle("Library")
        .toolbarBackground(.hidden, for: .navigationBar)
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

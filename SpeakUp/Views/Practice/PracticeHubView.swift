import SwiftUI
import SwiftData

struct PracticeHubView: View {
    @State private var selectedSection: PracticeSection = .history

    let onSelectPrompt: (Prompt) -> Void
    let onSelectRecording: (String) -> Void
    var onShowBeforeAfter: () -> Void = {}
    var onShowJournalExport: () -> Void = {}
    var onStartStoryPractice: ((Story) -> Void)? = nil
    var onSendToWarmUp: ((Story) -> Void)? = nil
    var onSendToDrill: ((Story) -> Void)? = nil
    var storiesViewModel: StoriesViewModel

    // MARK: - Body

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                sectionPicker
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                switch selectedSection {
                case .history:
                    HistoryView(
                        onSelectRecording: onSelectRecording,
                        onShowBeforeAfter: onShowBeforeAfter,
                        onShowJournalExport: onShowJournalExport
                    )
                case .prompts:
                    AllPromptsView(onSelectPrompt: onSelectPrompt)
                case .journal:
                    StoriesListView(
                        viewModel: storiesViewModel,
                        onStartPractice: onStartStoryPractice,
                        onSendToWarmUp: onSendToWarmUp,
                        onSendToDrill: onSendToDrill
                    )
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(PracticeSection.allCases) { section in
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.25)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.caption2.weight(.semibold))

                        Text(section.label)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(selectedSection == section ? .white : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selectedSection == section {
                            Capsule()
                                .fill(AppColors.primary.opacity(0.6))
                        } else {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule()
                                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Practice Section Enum

enum PracticeSection: String, CaseIterable, Identifiable {
    case history
    case prompts
    case journal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .history: return "Recordings"
        case .prompts: return "Prompts"
        case .journal: return "Journal"
        }
    }

    var title: String {
        switch self {
        case .history: return "Recordings"
        case .prompts: return "Prompts"
        case .journal: return "Journal"
        }
    }

    var icon: String {
        switch self {
        case .history: return "clock"
        case .prompts: return "text.bubble"
        case .journal: return "text.book.closed"
        }
    }
}

#Preview {
    NavigationStack {
        PracticeHubView(
            onSelectPrompt: { _ in },
            onSelectRecording: { _ in },
            storiesViewModel: StoriesViewModel()
        )
    }
    .modelContainer(for: [Recording.self, Prompt.self, UserSettings.self], inMemory: true)
}

import SwiftUI
import SwiftData

struct PracticeHubView: View {
    @State private var selectedSection: PracticeSection = .prompts
    @Namespace private var pickerNamespace

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
                    AllPromptsView(onSelectPrompt: onSelectPrompt)
                        .transition(.opacity)
                case .journal:
                    StoriesListView(
                        viewModel: storiesViewModel,
                        onStartPractice: onStartStoryPractice,
                        onSendToWarmUp: onSendToWarmUp,
                        onSendToDrill: onSendToDrill
                    )
                    .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                sectionPicker
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(Color(red: 0.05, green: 0.07, blue: 0.16))
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(PracticeSection.allCases) { section in
                sectionPickerItem(section)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    @ViewBuilder
    private func sectionPickerItem(_ section: PracticeSection) -> some View {
        let isSelected = selectedSection == section
        Button {
            guard selectedSection != section else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(section.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.primary.opacity(0.85),
                                    AppColors.primary.opacity(0.55)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                        .shadow(color: AppColors.primary.opacity(0.45), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "pickerSelection", in: pickerNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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

    var title: String {
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

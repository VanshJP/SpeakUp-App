import SwiftUI
import SwiftData

struct StoryWordPickerSheet: View {
    let content: String
    @Bindable var viewModel: StoriesViewModel

    @Environment(\.dismiss) private var dismiss
    @Query private var userSettings: [UserSettings]

    @State private var selectedWords: Set<String> = []
    @State private var showAddedConfirmation = false
    @State private var addedDestination = ""

    private var words: [String] {
        content
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
    }

    private var uniqueWords: [String] {
        var seen = Set<String>()
        return words.filter { word in
            let lower = word.lowercased()
            guard !seen.contains(lower) else { return false }
            seen.insert(lower)
            return true
        }
    }

    var body: some View {
        ZStack {
            AppBackground(style: .subtle)

            VStack(spacing: 16) {
                instructionCard

                ScrollView {
                    FlowLayout(spacing: 8) {
                        ForEach(uniqueWords, id: \.self) { word in
                            wordChip(word)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if !selectedWords.isEmpty {
                    actionButtons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle("Add to Word Bank")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .overlay {
            if showAddedConfirmation {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                        Text("Added \(selectedWords.count) words to \(addedDestination)")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassBackground(cornerRadius: 12)
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Subviews

    private var instructionCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "text.badge.plus")
                    .font(.title3)
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap words to select")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text("Then add them to your vocabulary or dictation dictionary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func wordChip(_ word: String) -> some View {
        let isSelected = selectedWords.contains(word)
        return Button {
            Haptics.light()
            if isSelected {
                selectedWords.remove(word)
            } else {
                selectedWords.insert(word)
            }
        } label: {
            Text(word)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule().fill(AppColors.primary.opacity(0.6))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Text("\(selectedWords.count) words selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                GlassButton(title: "Add to Vocabulary", icon: "text.book.closed", style: .primary, size: .medium) {
                    addToVocab()
                }

                GlassButton(title: "Add to Dictionary", icon: "character.book.closed", style: .secondary, size: .medium) {
                    addToDictation()
                }
            }
        }
    }

    // MARK: - Actions

    private func addToVocab() {
        guard let settings = userSettings.first else { return }
        viewModel.addWordsToVocab(words: Array(selectedWords), settings: settings)
        showConfirmation(destination: "Vocabulary")
    }

    private func addToDictation() {
        guard let settings = userSettings.first else { return }
        viewModel.addWordsToDictation(words: Array(selectedWords), settings: settings)
        showConfirmation(destination: "Dictation Dictionary")
    }

    private func showConfirmation(destination: String) {
        Haptics.success()
        addedDestination = destination
        withAnimation(.spring(response: 0.3)) {
            showAddedConfirmation = true
        }
        selectedWords.removeAll()
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                showAddedConfirmation = false
            }
        }
    }
}

import SwiftUI
import SwiftData

struct AddPromptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var promptText = ""
    @State private var selectedCategory: PromptCategory = .personalGrowth
    @State private var selectedDifficulty: PromptDifficulty = .medium
    @FocusState private var isTextFocused: Bool

    private var trimmedText: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView {
                    VStack(spacing: 20) {
                        promptTextSection
                        categorySection
                        difficultySection
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                // Save rides in the bar. At the foot of the form it sat
                // under the keyboard while you typed.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePrompt() }
                        .disabled(trimmedText.isEmpty)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear { isTextFocused = true }
    }

    // MARK: - Prompt Text

    private var promptTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Prompt")

            GlassCard {
                TextField("Enter your prompt…", text: $promptText, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.body)
                    .focused($isTextFocused)
            }

            Text("Write a question or topic you'd like to practice speaking about.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Category")

            FlowLayout(spacing: 8) {
                ForEach(PromptCategory.allCases, id: \.self) { category in
                    FilterChip(
                        title: category.shortName,
                        icon: category.iconName,
                        isSelected: selectedCategory == category,
                        tint: category.color
                    ) {
                        Haptics.selection()
                        selectedCategory = category
                    }
                }
            }
        }
    }

    // MARK: - Difficulty

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Difficulty")

            HStack(spacing: 8) {
                ForEach(PromptDifficulty.allCases, id: \.self) { difficulty in
                    FilterChip(
                        title: difficulty.displayName,
                        icon: difficulty.iconName,
                        isSelected: selectedDifficulty == difficulty,
                        tint: difficulty.color
                    ) {
                        Haptics.selection()
                        selectedDifficulty = difficulty
                    }
                }
            }
        }
    }

    // MARK: - Save

    private func savePrompt() {
        guard !trimmedText.isEmpty else { return }

        let prompt = Prompt(
            id: "user-\(UUID().uuidString)",
            text: trimmedText,
            category: selectedCategory.rawValue,
            difficulty: selectedDifficulty,
            isUserCreated: true
        )
        modelContext.insert(prompt)
        try? modelContext.save()

        Haptics.success()
        dismiss()
    }
}

#Preview {
    AddPromptView()
        .modelContainer(for: [Prompt.self], inMemory: true)
}

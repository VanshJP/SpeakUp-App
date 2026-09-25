import SwiftUI
import SwiftData

struct BatchAddPromptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingPrompts: [Prompt]

    @State private var inputText = ""
    @State private var selectedCategory: PromptCategory = .personalGrowth
    @State private var selectedDifficulty: PromptDifficulty = .medium
    @FocusState private var isTextFocused: Bool

    /// One prompt per non-empty line, less any line the library already has
    /// or the paste repeats - the rule a CSV import applies.
    private var pastedPrompts: (unique: [String], duplicates: Int) {
        let lines = inputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return PromptCSVService.removingDuplicates(lines, text: { $0 }, existing: existingPrompts.map(\.text))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                PageScrollView {
                    VStack(spacing: 20) {
                        textInputSection
                        categorySection
                        difficultySection
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add Multiple Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                // In the bar, not at the foot of the form under the keyboard.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { savePrompts() }
                        .disabled(pastedPrompts.unique.isEmpty)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear { isTextFocused = true }
    }

    // MARK: - Text Input

    private var textInputSection: some View {
        let pasted = pastedPrompts

        return VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader("Prompts")

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .focused($isTextFocused)

                    Divider()

                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("One prompt per line")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(countLabel(pasted))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(pasted.unique.isEmpty ? Color.secondary : AppColors.primary)
                    }
                }
            }
        }
    }

    private func countLabel(_ pasted: (unique: [String], duplicates: Int)) -> String {
        let count = pasted.unique.count
        guard pasted.duplicates > 0 else {
            return "\(count) prompt\(count == 1 ? "" : "s") detected"
        }
        return "\(count) new · \(pasted.duplicates) duplicate\(pasted.duplicates == 1 ? "" : "s")"
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

            Text("All prompts will be added to this category.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
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

    private func savePrompts() {
        for line in pastedPrompts.unique {
            let prompt = Prompt(
                id: "user-\(UUID().uuidString)",
                text: line,
                category: selectedCategory.rawValue,
                difficulty: selectedDifficulty,
                isUserCreated: true
            )
            modelContext.insert(prompt)
        }
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }
}

#Preview {
    BatchAddPromptsView()
        .modelContainer(for: [Prompt.self], inMemory: true)
}

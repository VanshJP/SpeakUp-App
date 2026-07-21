import SwiftUI
import SwiftData

struct AddPromptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var promptText = ""
    @State private var selectedCategory: PromptCategory = .personalGrowth
    @State private var selectedDifficulty: PromptDifficulty = .medium

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(style: .subtle)

                ScrollView {
                    VStack(spacing: 20) {
                        promptTextSection
                        categorySection
                        difficultySection
                        saveButton
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
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Prompt Text

    private var promptTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prompt", systemImage: "text.bubble")
                .font(.headline)

            GlassCard {
                TextField("Enter your prompt...", text: $promptText, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.body)
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
            Label("Category", systemImage: "folder")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(PromptCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            Haptics.selection()
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 13))
                                .foregroundStyle(selectedCategory == category ? .white : category.color)

                            Text(category.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectedCategory == category ? .white : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background {
                            if selectedCategory == category {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(category.color.opacity(0.7))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Difficulty

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Difficulty", systemImage: "speedometer")
                .font(.headline)

            GlassCard {
                HStack(spacing: 12) {
                    ForEach(PromptDifficulty.allCases, id: \.self) { difficulty in
                        Button {
                            Haptics.selection()
                            selectedDifficulty = difficulty
                        } label: {
                            Text(difficulty.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(selectedDifficulty == difficulty ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background {
                                    if selectedDifficulty == difficulty {
                                        Capsule()
                                            .fill(difficulty.color.opacity(0.7))
                                    } else {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                    }
                                }
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        GlassButton(
            title: "Save Prompt",
            icon: "plus.circle.fill",
            style: .primary,
            size: .large,
            fullWidth: true
        ) {
            savePrompt()
        }
        .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        .padding(.top, 8)
    }

    // MARK: - Save

    private func savePrompt() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let prompt = Prompt(
            id: "user-\(UUID().uuidString)",
            text: trimmed,
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
